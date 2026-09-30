package com.trek.trek

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * The "Next trip" home-screen widget: a countdown to the signed-in account's
 * next trip, or the current day of a trip in progress. Redrawn whenever the
 * app publishes new data and on the periodic update in
 * res/xml/next_trip_widget_info.xml, so the countdown moves on each day
 * without the app running. Tapping it opens the app.
 */
class NextTripWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val content = NextTripWidgetContent.from(
            widgetData.getString(CANDIDATES_KEY, null),
            localEpochDay(),
        )
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_trip_widget)
            bind(context, views, content)
            views.setOnClickPendingIntent(R.id.next_trip_widget_root, launchIntent(context))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun bind(context: Context, views: RemoteViews, content: NextTripWidgetContent) {
        val res = context.resources
        val (title, status) = when (content) {
            NextTripWidgetContent.SignedOut ->
                null to res.getString(R.string.next_trip_widget_signed_out)
            NextTripWidgetContent.NoUpcomingTrip ->
                null to res.getString(R.string.next_trip_widget_none)
            is NextTripWidgetContent.Upcoming -> content.title to
                if (content.daysUntil == 1) {
                    res.getString(R.string.next_trip_widget_tomorrow)
                } else {
                    res.getQuantityString(
                        R.plurals.next_trip_widget_in_days,
                        content.daysUntil,
                        content.daysUntil,
                    )
                }
            is NextTripWidgetContent.InProgress -> content.title to
                if (content.totalDays != null) {
                    res.getString(R.string.next_trip_widget_day_of, content.day, content.totalDays)
                } else {
                    res.getString(R.string.next_trip_widget_day, content.day)
                }
        }
        views.setTextViewText(R.id.next_trip_widget_status, status)
        if (title != null) {
            views.setTextViewText(R.id.next_trip_widget_title, title)
            views.setViewVisibility(R.id.next_trip_widget_title, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.next_trip_widget_title, View.GONE)
        }
    }

    private fun launchIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun localEpochDay(): Long {
        val now = Calendar.getInstance()
        return NextTripWidgetContent.epochDay(
            now.get(Calendar.YEAR).toLong(),
            (now.get(Calendar.MONTH) + 1).toLong(),
            now.get(Calendar.DAY_OF_MONTH).toLong(),
        )
    }

    companion object {
        /** Must match `NextTripWidgetKeys.candidates` on the Dart side. */
        const val CANDIDATES_KEY = "next_trip.candidates"
    }
}
