package com.himanusia.itstheday

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class ItsTheDayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateAll(context, ids)
    }

    companion object {
        private const val WIDGET_PREFS = "itstheday_widget"

        fun updateAll(context: Context, widgetIds: IntArray? = null) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = widgetIds ?: manager.getAppWidgetIds(
                ComponentName(context, ItsTheDayWidgetProvider::class.java),
            )
            ids.forEach { manager.updateAppWidget(it, buildRemoteViews(context)) }
        }

        // Compare calendar labels in UTC so a 23/25-hour DST day is still one day.
        private fun dayLabel(date: java.util.Date): Long {
            val local = Calendar.getInstance().apply { time = date }
            return Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis / 86400000L
        }

        private fun daysText(days: Long): String = when {
            days < 0 -> "D+${-days}"
            days == 0L -> "D-DAY"
            else -> "D-$days"
        }

        private fun buildRemoteViews(context: Context): RemoteViews {
            val p = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
            val title = p.getString("title", null).orEmpty().ifBlank { "Add a goal or countdown" }
            val kind = p.getString("focusKind", "event")
            var countdown = p.getString("countdown", null).orEmpty().ifBlank { "—" }
            var status = p.getString("status", null).orEmpty().ifBlank { "FOCUS" }
            val progress = p.getString("progress", "").orEmpty()
            val now = java.util.Date()
            if (kind == "goal") {
                try {
                    val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
                    val deadline = format.parse(p.getString("goalDeadline", "").orEmpty())
                    if (deadline != null) countdown = daysText(dayLabel(deadline) - dayLabel(now))
                } catch (_: Exception) { /* Preserve last good widget label. */ }
                status = if (status == "completed") "COMPLETED · $progress" else progress
            } else {
                val time = p.getLong("eventTime", 0L)
                if (time > 0L) {
                    val days = dayLabel(java.util.Date(time)) - dayLabel(now)
                    countdown = daysText(days)
                    status = when {
                        p.getBoolean("allDay", false) && days == 0L -> "TODAY"
                        time < now.time && !p.getBoolean("allDay", false) || days < 0L -> "OVERDUE"
                        days == 0L -> "TODAY"
                        else -> "UPCOMING"
                    }
                }
            }
            val views = RemoteViews(context.packageName, R.layout.itstheday_widget)
            views.setTextViewText(R.id.widget_status, status)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_countdown, countdown)
            val launch = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("focusId", p.getString("eventId", ""))
                putExtra("focusKind", kind)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, launch, flags))
            return views
        }
    }
}
