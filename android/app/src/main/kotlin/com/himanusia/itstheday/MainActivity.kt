package com.himanusia.itstheday

import android.Manifest
import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CALENDAR_CHANNEL = "itstheday/calendar"
        private const val WIDGET_CHANNEL = "itstheday/widget"
        private const val READ_CALENDAR_REQUEST = 701
        private const val WIDGET_PREFS = "itstheday_widget"
        private const val KEY_TITLE = "title"
        private const val KEY_COUNTDOWN = "countdown"
        private const val KEY_STATUS = "status"
        private const val KEY_EVENT_ID = "eventId"
    }

    private var widgetChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        widgetChannel?.invokeMethod("openWidgetFocus", launchFocus())
    }

    private fun launchFocus(): Map<String, String>? {
        val id = intent?.getStringExtra("focusId") ?: return null
        val kind = intent?.getStringExtra("focusKind") ?: return null
        return mapOf("id" to id, "kind" to kind)
    }

    private var pendingCalendarPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestReadCalendar" -> requestCalendarPermission(result)
                "getUpcomingCalendarEvents" -> getUpcomingCalendarEvents(call, result)
                else -> result.notImplemented()
            }
        }

        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        )
        widgetChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchFocus" -> result.success(launchFocus())
                "updateWidget" -> updateWidget(call, result)
                "clearWidget" -> clearWidget(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CALENDAR,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }

        if (pendingCalendarPermission != null) {
            result.error("permission_in_progress", "Calendar permission is already being requested.", null)
            return
        }
        pendingCalendarPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CALENDAR),
            READ_CALENDAR_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != READ_CALENDAR_REQUEST) return
        val result = pendingCalendarPermission
        pendingCalendarPermission = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result?.success(if (granted) "granted" else "denied")
    }

    private fun getUpcomingCalendarEvents(call: MethodCall, result: MethodChannel.Result) {
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_CALENDAR,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission_denied", "READ_CALENDAR has not been granted.", null)
            return
        }

        val fromMillis = call.argument<Number>("fromMillis")?.toLong()
            ?: System.currentTimeMillis()
        val toMillis = call.argument<Number>("toMillis")?.toLong()
            ?: fromMillis + 365L * 24L * 60L * 60L * 1000L
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
        )

        try {
            val events = mutableListOf<Map<String, Any?>>()
            val cursor = CalendarContract.Instances.query(
                contentResolver,
                projection,
                fromMillis,
                toMillis,
                null,
            )
            cursor.use {
                val eventIdColumn = it.getColumnIndex(CalendarContract.Instances.EVENT_ID)
                val titleColumn = it.getColumnIndex(CalendarContract.Instances.TITLE)
                val beginColumn = it.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endColumn = it.getColumnIndex(CalendarContract.Instances.END)
                val allDayColumn = it.getColumnIndex(CalendarContract.Instances.ALL_DAY)
                val locationColumn = it.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
                val calendarNameColumn = it.getColumnIndex(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
                while (it.moveToNext()) {
                    if (eventIdColumn < 0 || titleColumn < 0 || beginColumn < 0) continue
                    val title = it.getString(titleColumn)?.trim().orEmpty()
                    if (title.isEmpty()) continue
                    val begin = it.getLong(beginColumn)
                    val end = if (endColumn >= 0) it.getLong(endColumn) else begin
                    events.add(
                        mapOf(
                            "id" to it.getLong(eventIdColumn).toString(),
                            "title" to title,
                            "startMillis" to begin,
                            "endMillis" to end,
                            "allDay" to (allDayColumn >= 0 && it.getInt(allDayColumn) == 1),
                            "location" to if (locationColumn >= 0) it.getString(locationColumn) else null,
                            "calendarName" to if (calendarNameColumn >= 0) it.getString(calendarNameColumn) else null,
                        ),
                    )
                }
            }
            events.sortBy { (it["startMillis"] as? Long) ?: Long.MAX_VALUE }
            result.success(events)
        } catch (security: SecurityException) {
            result.error("permission_denied", security.message ?: "Calendar access was denied.", null)
        } catch (error: Exception) {
            result.error("calendar_read_error", error.message ?: "Could not read the calendar.", null)
        }
    }

    private fun updateWidget(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val preferences = getSharedPreferences(WIDGET_PREFS, MODE_PRIVATE)
        preferences.edit()
            .putString(KEY_TITLE, arguments?.get("title")?.toString().orEmpty())
            .putString(KEY_COUNTDOWN, arguments?.get("countdown")?.toString().orEmpty())
            .putString(KEY_STATUS, arguments?.get("status")?.toString().orEmpty())
            .putString(KEY_EVENT_ID, arguments?.get("eventId")?.toString().orEmpty())
            .putString("focusKind", arguments?.get("focusKind")?.toString().orEmpty())
            .putString("goalDeadline", arguments?.get("goalDeadline")?.toString().orEmpty())
            .putString("progress", arguments?.get("progress")?.toString().orEmpty())
            .putLong("eventTime", (arguments?.get("eventTime") as? Number)?.toLong() ?: 0L)
            .putBoolean("allDay", arguments?.get("allDay") as? Boolean ?: false)
            .apply()
        updateAllWidgets()
        result.success(null)
    }

    private fun clearWidget(result: MethodChannel.Result) {
        getSharedPreferences(WIDGET_PREFS, MODE_PRIVATE).edit().clear().apply()
        updateAllWidgets()
        result.success(null)
    }

    private fun updateAllWidgets() {
        val manager = AppWidgetManager.getInstance(this)
        val component = ComponentName(this, ItsTheDayWidgetProvider::class.java)
        val ids = manager.getAppWidgetIds(component)
        if (ids.isNotEmpty()) {
            ItsTheDayWidgetProvider.updateAll(this, ids)
        }
    }
}
