package com.example.budgie_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

class DailySpendWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val PREFS_NAME = "daily_spend_widget_prefs"
        private const val KEY_TOTAL_MINOR = "today_total_minor"
        private const val KEY_DATE = "today_date"
        private const val KEY_LAST_ADDED_MINOR = "last_added_minor"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_WIDGET_EVENT_QUEUE = "flutter.widget_daily_spend_events_v1"
        private const val MAX_SYNC_EVENTS = 120
        const val ACTION_WIDGET_REFRESH = "com.example.budgie_flutter.widget.REFRESH"

        fun appendWidgetSpendEvent(
            context: Context,
            amountMinor: Long,
            dateIso: String,
        ) {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_WIDGET_EVENT_QUEUE, "[]") ?: "[]"
            val queue = try {
                JSONArray(raw)
            } catch (_: Exception) {
                JSONArray()
            }

            queue.put(
                JSONObject()
                    .put("eventId", UUID.randomUUID().toString())
                    .put("type", "add")
                    .put("amountMinor", amountMinor)
                    .put("dateIso", dateIso)
                    .put("createdAtMs", System.currentTimeMillis())
                    .put("retries", 0)
                    .put("sourceVersion", 2),
            )

            while (queue.length() > MAX_SYNC_EVENTS) {
                queue.remove(0)
            }

            prefs.edit().putString(KEY_WIDGET_EVENT_QUEUE, queue.toString()).apply()
        }

        fun updateWidgetLocalState(
            context: Context,
            amountMinor: Long,
            dateIso: String,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val todayTotalMinor = if (prefs.getString(KEY_DATE, null) == dateIso) {
                prefs.getLong(KEY_TOTAL_MINOR, 0L)
            } else {
                0L
            }

            prefs.edit()
                .putString(KEY_DATE, dateIso)
                .putLong(KEY_TOTAL_MINOR, todayTotalMinor + amountMinor)
                .putLong(KEY_LAST_ADDED_MINOR, amountMinor)
                .apply()
        }

        fun requestWidgetRefresh(context: Context) {
            val intent = Intent(context, DailySpendWidgetProvider::class.java).apply {
                action = ACTION_WIDGET_REFRESH
            }
            context.sendBroadcast(intent)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == ACTION_WIDGET_REFRESH ||
            intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE
        ) {
            refreshAllWidgets(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.daily_spend_widget)
            bindActions(context, widgetId, views)
            bindState(context, views)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindActions(context: Context, widgetId: Int, views: RemoteViews) {
        val openInputIntent = Intent(context, WidgetQuickAddActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            3000 + widgetId,
            openInputIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_add_spending_button, pendingIntent)
    }

    private fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, DailySpendWidgetProvider::class.java))
        onUpdate(context, manager, ids)
    }

    private fun todayKey(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return formatter.format(Date())
    }

    private fun ensureTodayState(context: Context): android.content.SharedPreferences {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = todayKey()
        if (prefs.getString(KEY_DATE, null) != today) {
            prefs.edit()
                .putString(KEY_DATE, today)
                .putLong(KEY_TOTAL_MINOR, 0L)
                .putLong(KEY_LAST_ADDED_MINOR, 0L)
                .apply()
        }
        return prefs
    }

    private fun bindState(context: Context, views: RemoteViews) {
        val prefs = ensureTodayState(context)
        val totalMinor = prefs.getLong(KEY_TOTAL_MINOR, 0L)
        val lastAddedMinor = prefs.getLong(KEY_LAST_ADDED_MINOR, 0L)
        val total = totalMinor / 100.0
        val lastAdded = lastAddedMinor / 100.0
        val pendingCount = pendingEventCount(context)
        val currency = NumberFormat.getCurrencyInstance(Locale("en", "IN"))

        views.setTextViewText(R.id.widget_total_value, currency.format(total))
        views.setTextViewText(
            R.id.widget_last_entry_value,
            if (lastAdded > 0) "+ ${currency.format(lastAdded)}" else context.getString(R.string.daily_spend_widget_no_entries),
        )
        views.setTextViewText(
            R.id.widget_pending_value,
            if (pendingCount > 0) {
                context.getString(R.string.daily_spend_widget_pending_fmt, pendingCount)
            } else {
                context.getString(R.string.daily_spend_widget_pending_none)
            },
        )
        views.setTextColor(
            R.id.widget_pending_value,
            if (pendingCount > 0) Color.parseColor("#B45309") else Color.parseColor("#374151"),
        )
    }

    private fun pendingEventCount(context: Context): Int {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_WIDGET_EVENT_QUEUE, "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }.length()
    }
}
