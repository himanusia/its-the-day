package com.himanusia.itstheday

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class ItsTheDayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateWidget(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
        manager.updateAppWidget(
            appWidgetId,
            buildRemoteViews(context, appWidgetId, newOptions),
        )
    }

    companion object {
        private const val WIDGET_PREFS = "itstheday_widget"
        private const val KEY_TITLE = "title"
        private const val KEY_COUNTDOWN = "countdown"
        private const val KEY_STATUS = "status"
        private const val KEY_EVENT_ID = "eventId"
        private const val KEY_FOCUS_KIND = "focusKind"
        private const val KEY_GOAL_DEADLINE = "goalDeadline"
        private const val KEY_GOAL_COMPLETED = "goalCompleted"
        private const val KEY_GOAL_TARGET = "goalTarget"
        private const val KEY_GOAL_UNIT = "goalUnit"
        private const val KEY_PROGRESS = "progress"
        private const val KEY_EVENT_TIME = "eventTime"
        private const val KEY_ALL_DAY = "allDay"
        private const val MILLIS_PER_DAY = 86_400_000L
        private const val COMPACT_MAX_WIDTH_DP = 160
        private const val COMPACT_MAX_HEIGHT_DP = 100

        fun updateAll(context: Context, widgetIds: IntArray? = null) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = widgetIds ?: manager.getAppWidgetIds(
                ComponentName(context, ItsTheDayWidgetProvider::class.java),
            )
            ids.forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            manager.updateAppWidget(
                appWidgetId,
                buildRemoteViews(
                    context,
                    appWidgetId,
                    manager.getAppWidgetOptions(appWidgetId),
                ),
            )
        }

        private fun isCompact(options: Bundle): Boolean {
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            // A missing options bundle is treated as compact so the initial 1x1
            // layout cannot briefly render the larger view and clip its text.
            return minWidth <= 0 ||
                minHeight <= 0 ||
                minWidth < COMPACT_MAX_WIDTH_DP ||
                minHeight < COMPACT_MAX_HEIGHT_DP
        }

        // Compare local calendar labels in UTC so a 23/25-hour DST day is still one day.
        private fun dayLabel(date: Date): Long {
            val local = Calendar.getInstance().apply { time = date }
            val utcLabel = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(
                    local.get(Calendar.YEAR),
                    local.get(Calendar.MONTH),
                    local.get(Calendar.DAY_OF_MONTH),
                )
            }
            return Math.floorDiv(utcLabel.timeInMillis, MILLIS_PER_DAY)
        }

        private fun daysText(days: Long): String = when {
            days < 0 -> "D+${Math.abs(days)}"
            days == 0L -> "D-DAY"
            else -> "D-$days"
        }

        private fun parseCalendarDate(value: String): Date? {
            if (value.isBlank()) return null
            return try {
                SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                    isLenient = false
                }.parse(value)
            } catch (_: Exception) {
                null
            }
        }

        private fun progressText(completed: Long, target: Long, unit: String): String {
            val cleanUnit = unit.ifBlank { "items" }
            return "$completed/$target $cleanUnit"
        }

        private fun paceText(remaining: Long, days: Long, unit: String): String {
            // Guard both operands before the two integer divisions below.
            if (remaining <= 0L || days <= 0L) return ""
            val cleanUnit = unit.ifBlank { "items" }
            return if (remaining >= days) {
                val daily = remaining / days +
                    if (remaining % days == 0L) 0L else 1L
                "PACE · $daily $cleanUnit/day"
            } else {
                val interval = days / remaining
                val dayWord = if (interval == 1L) "day" else "days"
                "PACE · 1 $cleanUnit every $interval $dayWord"
            }
        }

        private fun buildRemoteViews(
            context: Context,
            appWidgetId: Int,
            options: Bundle,
        ): RemoteViews {
            val preferences = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
            val rawTitle = preferences.getString(KEY_TITLE, null).orEmpty().trim()
            val title = rawTitle.ifBlank { "Add a goal or countdown" }
            val focusId = preferences.getString(KEY_EVENT_ID, null).orEmpty()
            val kind = preferences.getString(KEY_FOCUS_KIND, "event")
                .orEmpty()
                .ifBlank { "event" }
            var countdown = preferences.getString(KEY_COUNTDOWN, null)
                .orEmpty()
                .ifBlank { "—" }
            var status = preferences.getString(KEY_STATUS, null)
                .orEmpty()
                .ifBlank { "FOCUS" }
                .uppercase(Locale.US)
            var progress = preferences.getString(KEY_PROGRESS, null).orEmpty()
            var pace = ""
            val hasFocus = rawTitle.isNotBlank() || focusId.isNotBlank()
            val now = Date()

            if (!hasFocus) {
                status = "EMPTY"
                countdown = "—"
                progress = ""
            } else if (kind == "goal") {
                val goalTarget = preferences.getLong(KEY_GOAL_TARGET, 0L).coerceAtLeast(0L)
                val goalCompleted = preferences
                    .getLong(KEY_GOAL_COMPLETED, 0L)
                    .coerceAtLeast(0L)
                val goalUnit = preferences.getString(KEY_GOAL_UNIT, null).orEmpty()
                if (goalTarget <= 0L) {
                    status = "EMPTY"
                    countdown = "—"
                    progress = ""
                } else {
                    val remaining = (goalTarget - goalCompleted).coerceAtLeast(0L)
                    progress = progressText(goalCompleted, goalTarget, goalUnit)
                    val deadline = parseCalendarDate(
                        preferences.getString(KEY_GOAL_DEADLINE, null).orEmpty(),
                    )
                    if (remaining == 0L) {
                        status = "COMPLETED"
                        countdown = "DONE"
                    } else if (deadline != null) {
                        val daysUntilDeadline = dayLabel(deadline) - dayLabel(now)
                        countdown = daysText(daysUntilDeadline)
                        status = when {
                            daysUntilDeadline < 0L -> "OVERDUE"
                            daysUntilDeadline == 0L -> "TODAY"
                            else -> "UPCOMING"
                        }
                        if (daysUntilDeadline >= 0L) {
                            // The deadline is inclusive: today contributes one available day.
                            pace = paceText(
                                remaining,
                                daysUntilDeadline + 1L,
                                goalUnit,
                            )
                        }
                    } else {
                        status = "EMPTY"
                        countdown = "—"
                        pace = ""
                    }
                }
            } else {
                val eventTime = preferences.getLong(KEY_EVENT_TIME, 0L)
                if (eventTime > 0L) {
                    val allDay = preferences.getBoolean(KEY_ALL_DAY, false)
                    val daysUntilEvent = dayLabel(Date(eventTime)) - dayLabel(now)
                    countdown = daysText(daysUntilEvent)
                    status = when {
                        daysUntilEvent < 0L -> "OVERDUE"
                        !allDay && eventTime < now.time -> "OVERDUE"
                        daysUntilEvent == 0L -> "TODAY"
                        else -> "UPCOMING"
                    }
                }
                progress = status
            }

            val compact = isCompact(options)
            val views = RemoteViews(
                context.packageName,
                if (compact) R.layout.itstheday_widget_compact else R.layout.itstheday_widget,
            )
            val rootId = if (compact) R.id.widget_compact_root else R.id.widget_root
            val compactProgress = when {
                status == "EMPTY" -> "EMPTY"
                status == "COMPLETED" -> "DONE · $progress"
                kind == "goal" -> "$status · $progress"
                else -> status
            }
            if (compact) {
                views.setTextViewText(R.id.widget_compact_title, title)
                views.setTextViewText(R.id.widget_compact_countdown, countdown)
                views.setTextViewText(R.id.widget_compact_progress, compactProgress)
            } else {
                views.setTextViewText(R.id.widget_status, status)
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(R.id.widget_countdown, countdown)
                views.setTextViewText(R.id.widget_progress, progress)
                views.setTextViewText(R.id.widget_pace, pace)
                views.setViewVisibility(
                    R.id.widget_pace,
                    if (pace.isBlank()) View.GONE else View.VISIBLE,
                )
            }

            val accessibility = listOf(title, status, countdown, progress, if (compact) "" else pace)
                .filter { it.isNotBlank() }
                .joinToString(", ")
            views.setContentDescription(rootId, accessibility)
            val launch = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("focusId", focusId)
                putExtra("focusKind", kind)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                })
            views.setOnClickPendingIntent(
                rootId,
                PendingIntent.getActivity(context, appWidgetId, launch, flags),
            )
            return views
        }
    }
}
