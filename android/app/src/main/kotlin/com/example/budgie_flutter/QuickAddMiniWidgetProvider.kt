package com.example.budgie_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class QuickAddMiniWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            intent.action == DailySpendWidgetProvider.ACTION_WIDGET_REFRESH
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
            val views = RemoteViews(context.packageName, R.layout.quick_add_mini_widget)
            bindActions(context, widgetId, views)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindActions(context: Context, widgetId: Int, views: RemoteViews) {
        val openInputIntent = Intent(context, WidgetQuickAddActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            4000 + widgetId,
            openInputIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        views.setOnClickPendingIntent(R.id.mini_widget_root, pendingIntent)
    }

    private fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, QuickAddMiniWidgetProvider::class.java))
        onUpdate(context, manager, ids)
    }
}
