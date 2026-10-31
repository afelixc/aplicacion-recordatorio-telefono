package com.afelixc.recordame

import android.app.Activity
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal "recordame/sonido": abre el selector de sonidos de Android y
 * reproduce un sonido para probarlo.
 */
class MainActivity : FlutterActivity() {
    private val pickRequest = 4711
    private var pendingPick: MethodChannel.Result? = null
    private var playing: Ringtone? = null
    private val handler = Handler(Looper.getMainLooper())

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
        handler.postDelayed({ stop() }, 4000)
    }

    private fun stop() {
        handler.removeCallbacksAndMessages(null)
        playing?.stop()
        playing = null
    }
}
