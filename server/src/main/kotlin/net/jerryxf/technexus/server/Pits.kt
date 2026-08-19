package net.jerryxf.technexus.server

import io.ktor.http.*
import io.ktor.http.content.CachingOptions
import io.ktor.server.application.*
import io.ktor.server.plugins.cachingheaders.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/**
 * Pit-floor data: the map, the team-to-address mapping, and the team list.
 *
 * All three are near-static. A pit map is drawn before an event and edited
 * rarely; the team list changes when a team drops. That is the opposite of
 * `/event/{event}`, which is written to protect a 15-second poll, so these
 * routes cache generously in *both* directions:
 *
 * - `s-maxage=900` — Cloudflare answers most of a venue from the edge.
 * - `max-age=300` — and unlike the schedule route, clients may reuse it too.
 *   Nothing here is polled, and the map is by far the largest payload the app
 *   fetches. Re-downloading it on every visit to the Pit tab would be the only
 *   reason it ever felt slow.
 *
 * There is no push path for any of this: the Nexus webhook fires on match
 * status, break times, alliances, announcements and parts requests — not on map
 * edits. The TTL is the entire freshness strategy, which is why it is minutes
 * rather than hours.
 */
fun Application.pits() = routing {
    /**
     * Raw pit map geometry.
     *
     * Nexus returns **404 for an event that exists but has no pit map**, which
     * is the common case rather than an error — most events never draw one.
     * [nexusBody] already relays 404 verbatim, so the client can tell "no map
     * published" apart from "the fetch failed" and say so. Do not collapse this
     * into a 502.
     */
    get("/event/{event}/map") {
        call.caching = mapCaching
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }
        proxyNexus(call, "event/$event/map", HttpStatusCode.NoContent)
    }

    /**
     * Team number to pit address.
     *
     * Independent of the map: this 404s only when the *event* doesn't exist, so
     * an event with addresses but no drawn map still answers here. An event
     * that exists with nothing assigned yet returns `{}` — an empty object, not
     * a 404, and not an error.
     */
    get("/event/{event}/pits") {
        call.caching = mapCaching
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }
        proxyNexus(call, "event/$event/pits")
    }

    /**
     * Teams attending, as a flat array of team numbers.
     *
     * The last rung of the Pit tab's fallback ladder, for an event with neither
     * a map nor assigned addresses. The same list is derivable from the union of
     * `redTeams` / `blueTeams` across `/event/{event}`, but that is empty until
     * the qualification schedule is published — which is exactly when someone is
     * most likely to be looking for it.
     */
    get("/event/{event}/teams") {
        call.caching = mapCaching
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }
        proxyNexus(call, "event/$event/teams")
    }
}

private val mapCaching = CachingOptions(
    CacheControl.MaxAge(
        maxAgeSeconds = 300,
        proxyMaxAgeSeconds = 900,
        visibility = CacheControl.Visibility.Public
    )
)
