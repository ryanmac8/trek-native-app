package com.trek.trek

import org.json.JSONArray
import org.json.JSONException

/**
 * What the "Next trip" widget shows, worked out from the candidate list the
 * Flutter side publishes (`NextTripWidgetKeys.candidates` in
 * lib/home_widgets/home_widget_publisher.dart) and the device's local date.
 *
 * The candidates are already sorted, so the widget shows the first one whose
 * last day (end date, else start date) is today or later. Doing this here, not
 * in Dart, keeps the countdown correct on later days without the app running.
 */
sealed class NextTripWidgetContent {
    /** No data published: nobody is signed in (or the app hasn't run yet). */
    object SignedOut : NextTripWidgetContent()

    /** Signed in, but no dated trip is running or ahead. */
    object NoUpcomingTrip : NextTripWidgetContent()

    /** [daysUntil] ≥ 1 days before the trip's first day. */
    data class Upcoming(val title: String, val daysUntil: Int) : NextTripWidgetContent()

    /** On day [day] of the trip; [totalDays] is null when it has no end date. */
    data class InProgress(val title: String, val day: Int, val totalDays: Int?) :
        NextTripWidgetContent()

    companion object {
        /**
         * [candidatesJson] is the published JSON array (or null when cleared);
         * [today] is the local date as an epoch day.
         */
        fun from(candidatesJson: String?, today: Long): NextTripWidgetContent {
            if (candidatesJson == null) return SignedOut
            val candidates = try {
                JSONArray(candidatesJson)
            } catch (e: JSONException) {
                return SignedOut
            }
            for (i in 0 until candidates.length()) {
                val trip = candidates.optJSONObject(i) ?: continue
                val start = epochDay(trip.optNullableString("start_date")) ?: continue
                val end = epochDay(trip.optNullableString("end_date"))
                if ((end ?: start) < today) continue
                val title = trip.optString("title")
                return if (start > today) {
                    Upcoming(title, (start - today).toInt())
                } else {
                    InProgress(
                        title,
                        (today - start).toInt() + 1,
                        end?.let { (it - start).toInt() + 1 },
                    )
                }
            }
            return NoUpcomingTrip
        }

        private fun org.json.JSONObject.optNullableString(name: String): String? =
            if (isNull(name)) null else optString(name)

        /** Days since 1970-01-01 for a `YYYY-MM-DD` string, or null if malformed. */
        fun epochDay(date: String?): Long? {
            val parts = date?.split("-") ?: return null
            if (parts.size != 3) return null
            val y = parts[0].toLongOrNull() ?: return null
            val m = parts[1].toLongOrNull() ?: return null
            val d = parts[2].toLongOrNull() ?: return null
            if (m !in 1..12 || d !in 1..31) return null
            return epochDay(y, m, d)
        }

        /** Proleptic Gregorian date → epoch day, without java.time (API 26+). */
        fun epochDay(year: Long, month: Long, day: Long): Long {
            val y = if (month <= 2) year - 1 else year
            val era = Math.floorDiv(y, 400L)
            val yoe = y - era * 400
            val mp = (month + 9) % 12
            val doy = (153 * mp + 2) / 5 + day - 1
            val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146097 + doe - 719468
        }
    }
}
