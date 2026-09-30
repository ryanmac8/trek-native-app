package com.trek.trek

import org.junit.Assert.assertEquals
import org.junit.Test

class NextTripWidgetContentTest {
    private val today = NextTripWidgetContent.epochDay("2026-09-30")!!

    private fun trip(id: Int, start: String?, end: String? = null): String {
        fun q(s: String?) = if (s == null) "null" else "\"$s\""
        return """{"id":$id,"title":"Trip $id","start_date":${q(start)},"end_date":${q(end)}}"""
    }

    private fun content(vararg trips: String) =
        NextTripWidgetContent.from("[${trips.joinToString(",")}]", today)

    @Test
    fun epochDayMatchesKnownDates() {
        assertEquals(0L, NextTripWidgetContent.epochDay("1970-01-01"))
        assertEquals(20727L, NextTripWidgetContent.epochDay("2026-10-01"))
        assertEquals(19782L, NextTripWidgetContent.epochDay("2024-02-29"))
        assertEquals(null, NextTripWidgetContent.epochDay("soon"))
        assertEquals(null, NextTripWidgetContent.epochDay(null))
    }

    @Test
    fun nothingPublishedIsSignedOut() {
        assertEquals(NextTripWidgetContent.SignedOut, NextTripWidgetContent.from(null, today))
        assertEquals(NextTripWidgetContent.SignedOut, NextTripWidgetContent.from("{bad", today))
    }

    @Test
    fun emptyListIsNoUpcomingTrip() {
        assertEquals(NextTripWidgetContent.NoUpcomingTrip, content())
    }

    @Test
    fun countsDownToAnUpcomingTrip() {
        assertEquals(
            NextTripWidgetContent.Upcoming("Trip 1", 33),
            content(trip(1, "2026-11-02", "2026-11-20")),
        )
    }

    @Test
    fun showsTheDayOfATripInProgress() {
        assertEquals(
            NextTripWidgetContent.InProgress("Trip 1", 3, 5),
            content(trip(1, "2026-09-28", "2026-10-02")),
        )
        assertEquals(
            NextTripWidgetContent.InProgress("Trip 2", 1, null),
            content(trip(2, "2026-09-30")),
        )
    }

    @Test
    fun skipsTripsThatHaveEndedSincePublishing() {
        assertEquals(
            NextTripWidgetContent.Upcoming("Trip 2", 5),
            content(trip(1, "2026-09-20", "2026-09-29"), trip(2, "2026-10-05", "2026-10-06")),
        )
        assertEquals(
            NextTripWidgetContent.NoUpcomingTrip,
            content(trip(1, "2026-09-20", "2026-09-29")),
        )
    }
}
