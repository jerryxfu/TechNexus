package net.jerryxf.technexus

import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import net.jerryxf.technexus.shared.PitAddress
import net.jerryxf.technexus.shared.PitMap
import net.jerryxf.technexus.shared.PitMapWire

/**
 * Pit-floor data for the Pit tab.
 *
 * Lives outside `Backend.kt` so the file Samy and I both touch stays small, and
 * because the pit endpoints need something the rest of the client does not: the
 * ability to distinguish *absent* from *broken*.
 */

/**
 * The outcome of asking for a pit map.
 *
 * Every other call in the client collapses failure to null, which is fine when
 * the only honest thing to say is "couldn't load it". It is wrong here. An
 * event with no pit map is the **normal** case — most events never draw one —
 * and telling someone their connection failed when the event simply doesn't
 * have a map sends them to go stand somewhere with better signal for nothing.
 *
 * Swift reads these with `as?`:
 *
 * ```swift
 * if let found = result as? PitMapResult.Available { … }
 * else if result is PitMapResult.NotPublished { … }
 * ```
 */
sealed class PitMapResult {
    /** Nexus has a map for this event. */
    data class Available(val map: PitMap) : PitMapResult()

    /** The event exists but no pit map was drawn. Nexus answers 404. */
    object NotPublished : PitMapResult()

    /** Network failure, bad response, or unparseable body. Worth retrying. */
    object Failed : PitMapResult()
}

/**
 * Fetch and flatten the pit map.
 *
 * Uses [HttpStatusCode] explicitly rather than letting a non-2xx throw, because
 * the 404 is load-bearing — see [PitMapResult].
 */
suspend fun getPitMap(eventKey: String): PitMapResult {
    return try {
        val response = client.get("$apiUrl/event/$eventKey/map")
        when (response.status) {
            HttpStatusCode.OK ->
                PitMapResult.Available(response.body<PitMapWire>().toPitMap())

            // 204, not 404. See the note on `notFoundStatus` in `Nexus.kt`.
            HttpStatusCode.NoContent -> PitMapResult.NotPublished
            else -> PitMapResult.Failed
        }
    } catch (e: Exception) {
        e.printStackTrace()
        PitMapResult.Failed
    }
}

/**
 * Team number to pit address, for events with addresses but no drawn map.
 *
 * Returns an empty list both when Nexus answers `{}` — an event with nothing
 * assigned yet — and on failure. The caller has already tried [getPitMap] by
 * this point and has a real error to show if that one came back
 * [PitMapResult.Failed]; a second error message for the fallback would only
 * stack.
 *
 * Sorted numerically by team, not lexically, so 3990 doesn't sort between 399
 * and 40.
 */
suspend fun getPitAddresses(eventKey: String): List<PitAddress> {
    return try {
        client.get("$apiUrl/event/$eventKey/pits")
            .body<Map<String, String>>()
            .map { (team, address) -> PitAddress(team, address) }
            .sortedBy { it.team.toIntOrNull() ?: Int.MAX_VALUE }
    } catch (e: Exception) {
        e.printStackTrace()
        emptyList()
    }
}

/**
 * Teams attending, soonest thing to a roster Nexus offers.
 *
 * The last rung: no map, no addresses, but at least confirmation that the event
 * has teams in it and that yours is one of them.
 */
suspend fun getEventTeams(eventKey: String): List<String> {
    return try {
        client.get("$apiUrl/event/$eventKey/teams")
            .body<List<String>>()
            .sortedBy { it.toIntOrNull() ?: Int.MAX_VALUE }
    } catch (e: Exception) {
        e.printStackTrace()
        emptyList()
    }
}