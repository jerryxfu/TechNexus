package net.jerryxf.technexus.server

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*

private const val NEXUS_API = "https://frc.nexus/api/v1"

/**
 * Forwards a GET to frc.nexus and returns the body on success.
 *
 * On any failure this **responds to the call itself** and returns null, so
 * callers can write `val body = nexusBody(call, path) ?: return@get`.
 *
 * Split out of [proxyNexus] so a route can transform the payload before relaying
 * it — see `enrichWithAlliances`. Routes that relay verbatim should keep calling
 * [proxyNexus].
 *
 * The previous version collapsed every non-200 into a bare 424 and sent the real
 * status and body to `println`. That cost us weeks: `/event/2026daly` was
 * returning **404 — the event does not exist** (Nexus purges past seasons), and
 * it looked identical to an authentication failure. The two now map differently,
 * and the upstream detail goes to the log where it can actually be read.
 *
 * Status mapping:
 * - **404** is relayed as 404. The client asked for an event that isn't there,
 *   which is worth telling the user precisely.
 * - **401 / 403** become 502. The *server's* key is wrong; that is not the
 *   caller's fault and shouldn't look like one. Logged at error level.
 * - anything else becomes 502.
 */
suspend fun nexusBody(
    call: ApplicationCall,
    path: String,
    /**
     * What to answer when frc.nexus says 404.
     *
     * `/map` passes 204: a missing pit map is the normal case, and leaving it as 404 makes it indistinguishable
     * from Ktor's own route-miss 404, so an undeployed server tells the client "this event has no map" instead of
     * "this endpoint is gone."
     */
    notFoundStatus: HttpStatusCode = HttpStatusCode.NotFound
): String? {
    val response = try {
        client.get("$NEXUS_API/$path") {
            headers.append("Nexus-Api-Key", Config.nexusApiKey)
        }
    } catch (e: Exception) {
        call.application.log.error("Could not reach frc.nexus for /{}", path, e)
        call.respond(HttpStatusCode.BadGateway, "Could not reach frc.nexus.")
        return null
    }

    if (response.status == HttpStatusCode.OK) return response.bodyAsText()

    val body = response.bodyAsText()
    when (response.status) {
        HttpStatusCode.NotFound -> {
            call.application.log.info("frc.nexus 404 for /{}: {}", path, body)
            // 204 cannot carry a body, so the upstream message goes to the log only.
            if (notFoundStatus == HttpStatusCode.NoContent) call.respond(HttpStatusCode.NoContent)
            else call.respond(notFoundStatus, body)
        }

        HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden -> {
            call.application.log.error(
                "frc.nexus rejected our API key ({}) for /{}: {}",
                response.status.value, path, body
            )
            call.respond(HttpStatusCode.BadGateway, "frc.nexus rejected the server's API key.")
        }

        else -> {
            call.application.log.error(
                "frc.nexus {} for /{}: {}", response.status.value, path, body
            )
            call.respond(HttpStatusCode.BadGateway, "frc.nexus returned ${response.status.value}.")
        }
    }
    return null
}

/** Relay a Nexus response verbatim. */
suspend fun proxyNexus(
    call: ApplicationCall,
    path: String,
    notFoundStatus: HttpStatusCode = HttpStatusCode.NotFound
) {
    val body = nexusBody(call, path, notFoundStatus) ?: return
    call.respondText(body, ContentType.Application.Json, HttpStatusCode.OK)
}
