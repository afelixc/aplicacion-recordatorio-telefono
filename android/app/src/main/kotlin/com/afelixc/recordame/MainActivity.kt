package com.afelixc.recordame

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recordame/icono")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cambiar" -> result.success(setIcon(call.argument<String>("id") ?: "clasico"))
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
                    "abrir" -> openBackup(result)
                    else -> if (!DriveFiles.handle(applicationContext, call, result)) result.notImplemented()
                }
            }
    }

    // --- Calendario del teléfono (el mismo que Google Calendar sincroniza) ---

    private fun hasCalendarPermission() =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun onCalendar(method: String, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        if (method != "pedirPermiso") {
            CalendarChannel(applicationContext).handle(call, result)
            return
        }
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

    private fun writeTo(uri: Uri, data: ByteArray) = DriveFiles.write(applicationContext, uri, data)

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

    /** Prende el ícono elegido (activity-alias) y apaga los demás. */
    private fun setIcon(id: String): Boolean {
        val ids = listOf("clasico", "rojo", "naranja", "verde", "violeta", "negro", "blanco", "celeste")
        if (id !in ids) return false
        return try {
            val pm = packageManager
            fun alias(n: String) = android.content.ComponentName(
                this, "$packageName.Icono${n.replaceFirstChar { it.uppercase() }}"
            )
            // Primero el nuevo, así nunca queda la app sin ícono.
            pm.setComponentEnabledSetting(
                alias(id), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP
            )
            for (other in ids) {
                if (other != id) {
                    pm.setComponentEnabledSetting(
                        alias(other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP
                    )
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
