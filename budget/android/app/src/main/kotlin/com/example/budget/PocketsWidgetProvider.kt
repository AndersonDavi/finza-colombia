package com.budget.tracker_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Free money of the groups and the chosen pockets, one per line
class PocketsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->

            val views = RemoteViews(context.packageName, R.layout.pockets_widget_layout).apply {
                try {
                  setTextViewText(R.id.pockets_title, widgetData.getString("pocketsTitle", null)
                  ?: "Free")
                  setTextViewText(R.id.pockets_amount, widgetData.getString("pocketsAmount", null)
                  ?: "0.00")
                  setTextViewText(R.id.pockets_lines, widgetData.getString("pocketsLines", null)
                  ?: "")
                }catch (e: Exception){}

                try {
                  setInt(R.id.widget_background, "setColorFilter",  android.graphics.Color.parseColor(widgetData.getString("widgetColorBackground", null)
                  ?: "#FFFFFF"));
                }catch (e: Exception){}

                try {
                  val alpha = Integer.parseInt(widgetData.getString("widgetAlpha", null)?: "255")
                  setInt(R.id.widget_background, "setImageAlpha",  alpha);
                }catch (e: Exception){}

                try {
                  val textColor = android.graphics.Color.parseColor(widgetData.getString("widgetColorText", null)
                  ?: "#FFFFFF")
                  setInt(R.id.pockets_title, "setTextColor", textColor)
                  setInt(R.id.pockets_amount, "setTextColor", textColor)
                  setInt(R.id.pockets_lines, "setTextColor", textColor)
                }catch (e: Exception){}

                // The card the app draws, with colors and icons; when it is
                // there the plain texts and background step aside
                try {
                  val imagePath = widgetData.getString("pocketsImage", null)
                  val bitmap = if (imagePath != null) BitmapFactory.decodeFile(imagePath) else null
                  if (bitmap != null) {
                    setImageViewBitmap(R.id.pockets_image, bitmap)
                    setViewVisibility(R.id.pockets_image, View.VISIBLE)
                    setViewVisibility(R.id.pockets_text, View.GONE)
                    setViewVisibility(R.id.widget_background, View.GONE)
                  }
                }catch (e: Exception){}

                try {
                  val pendingIntentWithData = HomeWidgetLaunchIntent.getActivity(
                          context,
                          MainActivity::class.java,
                          Uri.parse("openAppWidget"))
                  setOnClickPendingIntent(R.id.widget_container, pendingIntentWithData)
                }catch (e: Exception){}
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
