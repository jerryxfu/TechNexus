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
     * because it changes on the order of weeks, not seconds.
     */
    get("/events") {
        call.caching = CachingOptions(CacheControl.MaxAge(300))
        proxyNexus(call, "events")
    }

    get("/event/{event}") {
        call.caching = CachingOptions(CacheControl.MaxAge(15))
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }
        proxyNexus(call, "event/$event")
    }
}
