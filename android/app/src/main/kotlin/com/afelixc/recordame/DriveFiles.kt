package com.afelixc.recordame

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Leer y sobrescribir un archivo ya elegido con el selector de Android (por
 * ejemplo en Google Drive). Lo usan la app abierta (canal "recordame/copia")
 * y la revisión con la app cerrada (CalendarWorker), para la copia y para
 * los archivos de Gmail.
 */
object DriveFiles {
    private val handler = Handler(Looper.getMainLooper())

    /** Sobrescribe el archivo. Algunos proveedores no aceptan "wt": se prueba "w". */
    fun write(context: Context, uri: Uri, data: ByteArray): Boolean {
        for (mode in listOf("wt", "w")) {
            try {
                val out = context.contentResolver.openOutputStream(uri, mode) ?: continue
                out.use { it.write(data) }
                return true
            } catch (e: Exception) {
                // Se prueba el otro modo.
            }
        }
        return false
    }

    fun read(context: Context, uri: Uri): ByteArray? = try {
        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    } catch (e: Exception) {
        null
    }

    /** "escribir" y "leer" (en otro hilo). Devuelve false si no es uno de esos. */
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        val uri = call.argument<String>("uri")
        when (call.method) {
            "escribir" -> {
                val data = call.argument<ByteArray>("datos") ?: ByteArray(0)
                Thread {
                    val ok = uri != null && write(context, Uri.parse(uri), data)
                    handler.post { result.success(ok) }
                }.start()
            }
            "leer" -> Thread {
                val bytes = if (uri == null) null else read(context, Uri.parse(uri))
                handler.post { result.success(bytes) }
            }.start()
            else -> return false
        }
        return true
    }
}
