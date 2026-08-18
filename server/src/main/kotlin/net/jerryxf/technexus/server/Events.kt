package net.jerryxf.technexus.server

import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.application.*
import io.ktor.server.plugins.cachingheaders.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.events() = routing {
    /**
     * Every event Nexus currently knows about, keyed by event key.
     *
     * Nexus only carries current and upcoming events. Cached for five minutes
     * because it changes on the order of weeks, not seconds. A plain `max-age`
     * is right here: this is read when the event picker opens, not on a loop,
     * so a client holding it for five minutes is a feature.
     */
    get("/events") {
        call.caching = CachingOptions(CacheControl.MaxAge(300))
        proxyNexus(call, "events")
    }

    /**
     * Live event status.
     *
     * The cache directive splits deliberately between shared and private caches:
     *
     * - `s-maxage=15`: Cloudflare may hold this for 15 seconds. That is what
     *   keeps forty phones on one venue Wi-Fi from becoming forty upstream
     *   fetches, and it is what protects the frc.nexus quota.
     * - `max-age=0, must-revalidate`: no *client* may reuse it. Clients poll on
     *   the same 15s cadence, so a shared TTL and a private TTL of the same size
     *   leave no margin: a pull-to-refresh arriving mid-window would be answered
     *   from a local cache with no request sent and nothing changed on screen.
     *
     * This is also the only lever that reaches `NSURLSession`'s own `URLCache` on
     * iOS, which is disk-backed and cannot be configured from `commonMain`.
     *
     * A previous incarnation of this route set `max-age=15` and it made no
     * difference, because the zone's Browser Cache TTL was overriding every
     * response, including ones with no `Cache-Control` at all, overriding it to four hours.
     * If schedules ever freeze again, check the header on the wire before
     * touching any code:
     *
     *     curl -sSD - -o /dev/null https://nexus.jerryxf.net/event/demo1815
     *
     * The response is Nexus's, plus `redAlliance` / `blueAlliance` on playoff
     * matches (see `Alliances.kt`).
     */
    get("/event/{event}") {
        call.caching = CachingOptions(
            CacheControl.MaxAge(
                maxAgeSeconds = 0,
                proxyMaxAgeSeconds = 15,
                mustRevalidate = true,
                visibility = CacheControl.Visibility.Public
            )
        )
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }

        val body = nexusBody(call, "event/$event") ?: return@get
        call.respondText(
            enrichWithAlliances(body, event, call.application.log),
            ContentType.Application.Json,
            HttpStatusCode.OK
        )
    }
}
