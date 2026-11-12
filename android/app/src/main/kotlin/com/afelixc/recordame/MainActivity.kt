package com.afelixc.recordame

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
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
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopSound = Runnable { stop() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recordame/sonido")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "elegir" -> pick(call.argument<String>("actual"), result)
                    "probar" -> {
                        val uri = call.argument<String>("uri")
                        if (call.argument<Boolean>("aviso") == true) {
                            result.success(
                                playAsNotification(
                                    uri,
                                    call.argument<Boolean>("alarma") ?: false,
                                    call.argument<Int>("ms") ?: 4000,
                                    call.argument<Boolean>("repetir") ?: false,
                                ),
                            )
                        } else {
                            play(uri)
                            result.success(null)
                        }
                    }
                    "volumen" -> result.success(volumes())
                    "subirVolumen" -> result.success(raiseVolume(call.argument<Boolean>("alarma") ?: false))
                    "duracion" -> {
                        val uri = call.argument<String>("uri")
                        Thread {
                            val ms = durationOf(uri)
                            handler.post { result.success(ms) }
                        }.start()
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

    private fun target(uri: String?): Uri = if (uri == null) {
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    } else {
        Uri.parse(uri)
    }

    /** Escuchar un sonido mientras se elige (como antes de la versión 1.0.61). */
    private fun play(uri: String?) {
        stop()
        playing = RingtoneManager.getRingtone(this, target(uri))
        playing?.play()
        // Que no suene para siempre si se eligió un tono de llamada.
        handler.postDelayed(stopSound, 4000)
    }

    /**
     * "Probar": suena como va a sonar el aviso, con el volumen de las
     * notificaciones ([alarm]: con el de la alarma). [loop] lo repite hasta
     * que pasen [millis] (la prioridad alta). Devuelve el error, si hubo.
     */
    private fun playAsNotification(uri: String?, alarm: Boolean, millis: Int, loop: Boolean): String? {
        stop()
        val attrs = AudioAttributes.Builder()
            .setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        return try {
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(attrs)
            mp.setDataSource(this, target(uri))
            mp.isLooping = loop
            mp.setOnErrorListener { _, _, _ ->
                stop()
                true
            }
            mp.prepare()
            mp.start()
            handler.postDelayed(stopSound, millis.toLong().coerceIn(500L, 60000L))
            null
        } catch (e: Exception) {
            stop()
            // Si ese sonido no se puede abrir, al menos el de siempre.
            play(uri)
            e.message ?: e.javaClass.simpleName
        }
    }

    /** Volumen de las notificaciones y de la alarma (0 = no se escucha). */
    private fun volumes(): Map<String, Int> {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        fun muted(stream: Int) =
            if (Build.VERSION.SDK_INT >= 23 && audio.isStreamMute(stream)) 1 else 0
        return mapOf(
            "notificaciones" to audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION),
            "notificacionesMax" to audio.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION),
            "notificacionesMudo" to muted(AudioManager.STREAM_NOTIFICATION),
            "alarma" to audio.getStreamVolume(AudioManager.STREAM_ALARM),
            "alarmaMax" to audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            // 0 = silencio, 1 = vibrar, 2 = normal.
            "modo" to audio.ringerMode,
        )
    }

    /** Sube el volumen de las notificaciones (o de la alarma) a 3/4. */
    private fun raiseVolume(alarm: Boolean): Boolean = try {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        if (!alarm && audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
        }
        val stream = if (alarm) AudioManager.STREAM_ALARM else AudioManager.STREAM_NOTIFICATION
        if (Build.VERSION.SDK_INT >= 23) {
            audio.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
        }
        val max = audio.getStreamMaxVolume(stream)
        val want = (max * 3 + 3) / 4
        if (audio.getStreamVolume(stream) < want) {
            audio.setStreamVolume(stream, want, AudioManager.FLAG_SHOW_UI)
        }
        audio.getStreamVolume(stream) > 0
    } catch (e: Exception) {
        // Con "No molestar" prendido Android no deja: se abre el ajuste.
        false
    }

    /** Cuánto dura un sonido del teléfono, en milisegundos (null si no se sabe). */
    private fun durationOf(uri: String?): Int? {
        if (uri == null) return null
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, Uri.parse(uri))
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull()
        } catch (e: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Nada que hacer.
            }
        }
    }

    private fun stop() {
        handler.removeCallbacks(stopSound)
        playing?.stop()
        playing = null
        player?.let {
            try {
                it.stop()
            } catch (e: Exception) {
                // Ya estaba parado.
            }
            it.release()
        }
        player = null
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
