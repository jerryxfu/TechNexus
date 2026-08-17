package net.jerryxf.technexus.server

import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.application.*
import io.ktor.server.plugins.cachingheaders.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import net.jerryxf.technexus.shared.MatchId
import net.jerryxf.technexus.shared.MatchScore

fun Application.matches() = routing {
    get("/event/{event}/match/{matchId}") {
        call.caching = CachingOptions(CacheControl.MaxAge(3600))
        val event = call.parameters["event"]
        if (event.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, "Invalid event")
            return@get
        }
        val matchId = try {
            call.parameters["matchId"]?.let { MatchId.fromShort(it) }
        } catch (e: Exception) {
            call.application.log.warn("Unparseable match id {}", call.parameters["matchId"], e)
            null
        }
        if (matchId == null) {
            call.respond(HttpStatusCode.BadRequest, "Invalid match id")
            return@get
        }

        val resp =
            client.get("https://www.thebluealliance.com/api/v3/match/${matchId.getTBAKey(event)}") {
                headers.append("X-TBA-Auth-Key", Config.tbaApiKey)
            }
        if (resp.status != HttpStatusCode.OK) {
            // Same reasoning as proxyNexus: relay a missing match as missing,
            // and never lose the upstream detail to stdout.
            val body = resp.bodyAsText()
            if (resp.status == HttpStatusCode.NotFound) {
                call.application.log.info("TBA 404 for {}: {}", matchId.getTBAKey(event), body)
                call.respond(HttpStatusCode.NotFound, body)
            } else {
                call.application.log.error(
                    "TBA {} for {}: {}", resp.status.value, matchId.getTBAKey(event), body
                )
                call.respond(HttpStatusCode.BadGateway, "The Blue Alliance returned ${resp.status.value}.")
            }
            return@get
        }
        val score = resp.body<TBAMatch>()
        call.respond(MatchScore(score.alliances.blue.score, score.alliances.red.score))
    }
}
