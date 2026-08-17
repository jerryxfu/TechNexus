package net.jerryxf.technexus.server

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*

private const val NEXUS_API = "https://frc.nexus/api/v1"

/**
 * Forwards a GET to frc.nexus and relays the result.
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
suspend fun proxyNexus(call: ApplicationCall, path: String) {
    val response = try {
        client.get("$NEXUS_API/$path") {
            headers.append("Nexus-Api-Key", Config.nexusApiKey)
        }
    } catch (e: Exception) {
        call.application.log.error("Could not reach frc.nexus for /{}", path, e)
        call.respond(HttpStatusCode.BadGateway, "Could not reach frc.nexus.")
        return
    }

    if (response.status == HttpStatusCode.OK) {
        call.respondText(
            response.bodyAsText(),
            ContentType.Application.Json,
            HttpStatusCode.OK
        )
        return
    }

    val body = response.bodyAsText()
    when (response.status) {
        HttpStatusCode.NotFound -> {
            call.application.log.info("frc.nexus 404 for /{}: {}", path, body)
            call.respond(HttpStatusCode.NotFound, body)
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
}
