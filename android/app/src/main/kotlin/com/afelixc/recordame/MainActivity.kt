package com.afelixc.recordame

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import java.util.TimeZone
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal "recordame/sonido": abre el selector de sonidos de Android y
 * reproduce un sonido para probarlo.
 *
 * Canal "recordame/copia": guarda y abre la copia de seguridad con el
 * selector de archivos de Android (Google Drive, el teléfono, etc.).
 */
class MainActivity : FlutterActivity() {
    private val pickRequest = 4711
    private val createRequest = 4712
    private val openRequest = 4713
    private var pendingPick: MethodChannel.Result? = null
    private var pendingCreate: MethodChannel.Result? = null
    private var pendingCreateData: ByteArray? = null
    private var pendingOpen: MethodChannel.Result? = null
    private val calendarPermissionRequest = 4714
    private var pendingPermission: MethodChannel.Result? = null
    private var playing: Ringtone? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopSound = Runnable { stop() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recordame/sonido")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "elegir" -> pick(call.argument<String>("actual"), result)
                    "probar" -> {
                        play(call.argument<String>("uri"))
                        result.success(null)
                    }
                    "parar" -> {
                        stop()
                        result.success(null)
                    }
                    "nombre" -> result.success(titleOf(call.argument<String>("uri")))
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recordame/calendario")
            .setMethodCallHandler { call, result -> onCalendar(call.method, call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recordame/copia")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "crear" -> createBackup(
                        call.argument<String>("nombre") ?: "Recordame-copia.json",
                        call.argument<ByteArray>("datos") ?: ByteArray(0),
                        result,
                    )
                    "escribir" -> {
                        val uri = call.argument<String>("uri")
                        val data = call.argument<ByteArray>("datos") ?: ByteArray(0)
                        Thread {
                            val ok = uri != null && writeTo(Uri.parse(uri), data)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    "abrir" -> openBackup(result)
                    else -> result.notImplemented()
                }
            }
    }

    // --- Calendario del teléfono (el mismo que Google Calendar sincroniza) ---

    private fun hasCalendarPermission() =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                handler.post { result.success(value) }
            } catch (e: SecurityException) {
                handler.post { result.error("sin_permiso", "Falta el permiso de calendario", null) }
            } catch (e: Exception) {
                handler.post { result.error("error", e.message, null) }
            }
        }.start()
    }

    private fun onCalendar(method: String, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (method) {
            "tienePermiso" -> result.success(hasCalendarPermission())
            "pedirPermiso" -> {
                if (hasCalendarPermission()) {
                    result.success(true)
                    return
                }
                pendingPermission?.success(false)
                pendingPermission = result
                requestPermissions(
                    arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                    calendarPermissionRequest,
                )
            }
            "calendarios" -> background(result) { listCalendars() }
            "eventos" -> background(result) {
                listEvents(
                    (call.argument<Number>("calendario") ?: 0).toLong(),
                    (call.argument<Number>("desde") ?: 0).toLong(),
                    (call.argument<Number>("hasta") ?: 0).toLong(),
                )
            }
            "crear" -> background(result) {
                val values = eventValues(call)
                values.put(CalendarContract.Events.CALENDAR_ID, (call.argument<Number>("calendario") ?: 0).toLong())
                values.put(CalendarContract.Events.DESCRIPTION, "Creado por Recordame")
                // Sin avisos de Google Calendar: avisa Recordame.
                values.put(CalendarContract.Events.HAS_ALARM, 0)
                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                uri?.lastPathSegment
            }
            "actualizar" -> background(result) {
                val id = (call.argument<String>("id") ?: "0").toLong()
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
                contentResolver.update(uri, eventValues(call), null, null) > 0
            }
            "borrar" -> background(result) {
                val id = (call.argument<String>("id") ?: "0").toLong()
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
                contentResolver.delete(uri, null, null) > 0
            }
            else -> result.notImplemented()
        }
    }

    private fun eventValues(call: io.flutter.plugin.common.MethodCall): ContentValues {
        val start = (call.argument<Number>("inicio") ?: 0).toLong()
        val rrule = call.argument<String>("rrule")
        return ContentValues().apply {
            put(CalendarContract.Events.TITLE, call.argument<String>("titulo") ?: "")
            put(CalendarContract.Events.DTSTART, start)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            if (rrule != null) {
                put(CalendarContract.Events.RRULE, rrule)
                put(CalendarContract.Events.DURATION, "PT30M")
                putNull(CalendarContract.Events.DTEND)
            } else {
                putNull(CalendarContract.Events.RRULE)
                putNull(CalendarContract.Events.DURATION)
                put(CalendarContract.Events.DTEND, start + 30 * 60 * 1000)
            }
        }
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )
        contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val access = c.getInt(4)
                if (access < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) continue
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "nombre" to (c.getString(1) ?: ""),
                        "cuenta" to (c.getString(2) ?: ""),
                        "principal" to (c.getInt(3) == 1),
                    ),
                )
            }
        }
        return out
    }

    private fun listEvents(calendar: Long, from: Long, to: Long): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.RRULE,
        )
        contentResolver.query(
            uri,
            projection,
            "${CalendarContract.Instances.CALENDAR_ID} = ?",
            arrayOf(calendar.toString()),
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0).toString(),
                        "titulo" to (c.getString(1) ?: ""),
                        "inicio" to c.getLong(2),
                        "todoElDia" to (c.getInt(3) == 1),
                        "repite" to !c.getString(4).isNullOrEmpty(),
                    ),
                )
            }
        }
        return out
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != calendarPermissionRequest) return
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(hasCalendarPermission())
    }

    private fun createBackup(name: String, data: ByteArray, result: MethodChannel.Result) {
        pendingCreate?.success(null)
        pendingCreate = result
        pendingCreateData = data
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            startActivityForResult(intent, createRequest)
        } catch (e: Exception) {
            pendingCreate = null
            result.error("sin_selector", "Este teléfono no tiene selector de archivos", null)
        }
    }

    private fun openBackup(result: MethodChannel.Result) {
        pendingOpen?.success(null)
        pendingOpen = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            startActivityForResult(intent, openRequest)
        } catch (e: Exception) {
            pendingOpen = null
            result.error("sin_selector", "Este teléfono no tiene selector de archivos", null)
        }
    }

    /** Sobrescribe el archivo. Algunos proveedores no aceptan "wt": se prueba "w". */
    private fun writeTo(uri: Uri, data: ByteArray): Boolean {
        for (mode in listOf("wt", "w")) {
            try {
                val out = contentResolver.openOutputStream(uri, mode) ?: continue
                out.use { it.write(data) }
                return true
            } catch (e: Exception) {
                // Se prueba el otro modo.
            }
        }
        return false
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    private fun onBackupResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (requestCode == createRequest) {
            val result = pendingCreate ?: return
            val bytes = pendingCreateData ?: ByteArray(0)
            pendingCreate = null
            pendingCreateData = null
            if (uri == null) {
                result.success(null)
                return
            }
            // Para poder actualizar la copia sola los días siguientes.
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (e: Exception) {
                // Algunos lugares no lo permiten; la copia de hoy igual se guarda.
            }
            Thread {
                val ok = writeTo(uri, bytes)
                val name = displayName(uri) ?: "Recordame-copia.json"
                handler.post {
                    if (ok) {
                        result.success(mapOf("uri" to uri.toString(), "nombre" to name))
                    } else {
                        result.error("no_se_pudo", "No se pudo guardar en ese lugar", null)
                    }
                }
            }.start()
        } else {
            val result = pendingOpen ?: return
            pendingOpen = null
            if (uri == null) {
                result.success(null)
                return
            }
            Thread {
                val bytes = try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (e: Exception) {
                    null
                }
                handler.post {
                    if (bytes != null) {
                        result.success(bytes)
                    } else {
                        result.error("no_se_pudo", "No se pudo leer ese archivo", null)
                    }
                }
            }.start()
        }
    }

    private fun pick(current: String?, result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALL)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Sonido de los recordatorios")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            )
            if (current != null) {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(current))
            }
        }
        try {
            startActivityForResult(intent, pickRequest)
        } catch (e: Exception) {
            pendingPick = null
            result.error("sin_selector", "Este teléfono no tiene selector de sonidos", null)
        }
    }

    @Deprecated("Se usa startActivityForResult por simpleza")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == createRequest || requestCode == openRequest) {
            onBackupResult(requestCode, resultCode, data)
            return
        }
        if (requestCode != pickRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        if (uri == null) {
            result.success(null)
            return
        }
        result.success(mapOf("uri" to uri.toString(), "nombre" to (titleOf(uri.toString()) ?: "Sonido elegido")))
    }

    private fun titleOf(uri: String?): String? = try {
        RingtoneManager.getRingtone(this, Uri.parse(uri))?.getTitle(this)
    } catch (e: Exception) {
        null
    }

    private fun play(uri: String?) {
        stop()
        val target = if (uri == null) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } else {
            Uri.parse(uri)
        }
        playing = RingtoneManager.getRingtone(this, target)
        playing?.play()
        // Que no suene para siempre si se eligió un tono de llamada.
        handler.postDelayed(stopSound, 4000)
    }

    private fun stop() {
        handler.removeCallbacks(stopSound)
        playing?.stop()
        playing = null
    }
}
