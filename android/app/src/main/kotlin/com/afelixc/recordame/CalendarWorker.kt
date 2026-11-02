package com.afelixc.recordame

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * Revisa el calendario con la app cerrada y trae lo nuevo a Recordame.
 * También levanta lo que se hizo en Gmail en la compu (archivos en Drive).
 *
 * Se despierta de dos formas:
 *  1. "cambio": Android avisa cuando cambia algo en el calendario del teléfono
 *     (por ejemplo, llegó un evento anotado desde la compu). Casi al instante.
 *  2. "periodico": cada 15 minutos, de respaldo por si el aviso no llegó.
 *
 * Para hacer el trabajo arranca la parte de Dart de la app sin pantalla
 * (función calendarBackground en main.dart).
 */
class CalendarWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        withTimeoutOrNull(60_000) {
            withContext(Dispatchers.Main) { runDart() }
        }
        // El aviso de cambios sirve una sola vez: se vuelve a pedir.
        if (tags.contains(TAG_CHANGE)) scheduleChange(applicationContext, ExistingWorkPolicy.APPEND_OR_REPLACE)
        return Result.success()
    }

    private suspend fun runDart() = suspendCancellableCoroutine { cont ->
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = FlutterEngine(applicationContext)
        val main = Handler(Looper.getMainLooper())
        var finished = false
        fun finish() {
            if (finished) return
            finished = true
            main.post { engine.destroy() }
            if (cont.isActive) cont.resume(Unit)
        }
        val messenger = engine.dartExecutor.binaryMessenger
        val calendar = CalendarChannel(applicationContext)
        MethodChannel(messenger, "recordame/calendario").setMethodCallHandler { call, result ->
            calendar.handle(call, result)
        }
        // Archivos de Gmail en Drive (leer y escribir; elegirlos solo con la app abierta).
        MethodChannel(messenger, "recordame/copia").setMethodCallHandler { call, result ->
            if (!DriveFiles.handle(applicationContext, call, result)) result.notImplemented()
        }
        MethodChannel(messenger, "recordame/fondo").setMethodCallHandler { call, result ->
            result.success(null)
            if (call.method == "listo") finish()
        }
        cont.invokeOnCancellation { main.post { if (!finished) engine.destroy() } }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "calendarBackground"),
        )
    }

    companion object {
        private const val TAG_CHANGE = "cambio"
        private const val NAME_CHANGE = "recordame_calendario_cambio"
        private const val NAME_PERIODIC = "recordame_calendario_periodico"

        fun schedule(context: Context) {
            // El aviso de cambios del calendario solo con permiso (si es solo
            // por Gmail, alcanza con la revisión cada 15 minutos).
            if (CalendarChannel(context).hasPermission()) {
                scheduleChange(context, ExistingWorkPolicy.KEEP)
            }
            val periodic = PeriodicWorkRequestBuilder<CalendarWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, periodic)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(NAME_CHANGE)
            WorkManager.getInstance(context).cancelUniqueWork(NAME_PERIODIC)
        }

        private fun scheduleChange(context: Context, policy: ExistingWorkPolicy) {
            val constraints = Constraints.Builder()
                .addContentUriTrigger(CalendarContract.Events.CONTENT_URI, true)
                // Espera un poquito por si llegan varios cambios juntos.
                .setTriggerContentUpdateDelay(5, TimeUnit.SECONDS)
                .setTriggerContentMaxDelay(1, TimeUnit.MINUTES)
                .build()
            val request = OneTimeWorkRequestBuilder<CalendarWorker>()
                .setConstraints(constraints)
                .addTag(TAG_CHANGE)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NAME_CHANGE, policy, request)
        }
    }
}
