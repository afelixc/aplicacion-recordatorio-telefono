package com.afelixc.recordame

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.CalendarContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Canal "recordame/calendario": lee y escribe en el calendario del teléfono
 * (el mismo que Google Calendar sincroniza con la cuenta), y programa la
 * revisión del calendario con la app cerrada. Lo usan la app abierta
 * (MainActivity) y la revisión en segundo plano (CalendarWorker).
 */
class CalendarChannel(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val resolver get() = context.contentResolver

    fun hasPermission() =
        context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "tienePermiso" -> result.success(hasPermission())
            "bateriaLibre" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
            }
            "programarFondo" -> {
                CalendarWorker.schedule(context)
                result.success(null)
            }
            "cancelarFondo" -> {
                CalendarWorker.cancel(context)
                result.success(null)
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
                resolver.insert(CalendarContract.Events.CONTENT_URI, values)?.lastPathSegment
            }
            "actualizar" -> background(result) {
                val id = (call.argument<String>("id") ?: "0").toLong()
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
                resolver.update(uri, eventValues(call), null, null) > 0
            }
            // De estos ids, los que siguen en el calendario (no borrados).
            "existen" -> background(result) {
                val ids = (call.argument<List<String>>("ids") ?: emptyList())
                    .mapNotNull { it.toLongOrNull() }
                val alive = mutableListOf<String>()
                for (chunk in ids.chunked(300)) {
                    if (chunk.isEmpty()) continue
                    val where = "${CalendarContract.Events._ID} IN (${chunk.joinToString(",") { "?" }})"
                    resolver.query(
                        CalendarContract.Events.CONTENT_URI,
                        arrayOf(CalendarContract.Events._ID, CalendarContract.Events.DELETED),
                        where,
                        chunk.map { it.toString() }.toTypedArray(),
                        null,
                    )?.use { c ->
                        while (c.moveToNext()) {
                            if (c.getInt(1) == 0) alive.add(c.getLong(0).toString())
                        }
                    }
                }
                alive
            }
            "borrar" -> background(result) {
                val id = (call.argument<String>("id") ?: "0").toLong()
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
                resolver.delete(uri, null, null) > 0
            }
            else -> result.notImplemented()
        }
    }

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

    private fun eventValues(call: MethodCall): ContentValues {
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
            CalendarContract.Calendars.SYNC_EVENTS,
        )
        // Todos, también los que solo se pueden ver (por ejemplo uno que
        // comparten del laburo): de esos se puede traer pero no anotar.
        resolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "nombre" to (c.getString(1) ?: ""),
                        "cuenta" to (c.getString(2) ?: ""),
                        "principal" to (c.getInt(3) == 1),
                        "escribir" to (c.getInt(4) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR),
                        "sincroniza" to (c.isNull(5) || c.getInt(5) == 1),
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
        resolver.query(
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
}
