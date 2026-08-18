package net.jerryxf.technexus.server

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.*
import org.slf4j.Logger
import java.util.concurrent.ConcurrentHashMap

/**
 * Playoff alliance numbers, folded into the event payload.
 *
 * Nexus exposes alliances at `GET /event/{key}/alliances` as a two-dimensional
 * array: outer index is the seed, inner entries are team numbers in pick order:
 *
 * ```
 * [["3400","1900","200"], ["2000","2400","900"], ...]
 * ```
 *
 * so alliance number is `index + 1`. Outer entries may be null (that alliance
 * hasn't formed yet) and inner entries may be null (that slot hasn't been
 * picked), because the endpoint answers mid-selection.
 *
 * The join happens here rather than on the clients for three reasons: the raw
 * shape is `List<List<String?>?>`, and nested nullable-element lists are exactly
 * what SKIE mangles into `[Any]` on the Swift side; doing it once means Android
 * and iOS agree by construction; and the edge cache turns N devices polling into
 * one upstream fetch per minute rather than one per device.
 *
 * **Note on style:** the map below is built with an explicit `mutableMapOf` and
 * a `for` loop rather than `buildMap` and `forEach`. That is deliberate.
 * `buildMap` here has no expected type to infer from - the surrounding `catch`
 * returns, so there is nothing outside the builder to anchor `K` and `V` - and
 * Kotlin cannot propagate the constraints from a `put` nested two lambdas deep.
 * It fails with "cannot infer type for type parameter 'K'", and because every
 * downstream type then becomes an error type, the compiler reports receiver
 * mismatches against `kotlinx.io.Source` extensions that are merely on the
 * classpath via Ktor. That sends you looking in entirely the wrong place.
 * Explicit types cost one line and remove the trap.
 */

private const val ALLIANCE_TTL_MS = 60_000L

private class CachedAlliances(val teamToAlliance: Map<String, Int>, val atMs: Long)

/**
 * Per-instance memo. Cloud Run may run up to four instances, so the worst case
 * is four upstream fetches per TTL rather than one, which is fine, and cheaper
 * than the coordination needed to do better. A duplicate fetch under a race is
 * harmless, so this is a plain map rather than something guarded.
 */
private val allianceCache = ConcurrentHashMap<String, CachedAlliances>()

/**
 * Team number to alliance seed. Empty map when selection hasn't started; null
 * when the upstream call failed and we should leave the payload alone.
 */
private suspend fun allianceLookup(eventKey: String, log: Logger): Map<String, Int>? {
    val now = System.currentTimeMillis()
    allianceCache[eventKey]?.let { if (now - it.atMs < ALLIANCE_TTL_MS) return it.teamToAlliance }

    val response = try {
        client.get("https://frc.nexus/api/v1/event/$eventKey/alliances") {
            headers.append("Nexus-Api-Key", Config.nexusApiKey)
        }
    } catch (e: Exception) {
        log.warn("Could not reach frc.nexus for alliances of {}", eventKey, e)
        return null
    }

    if (response.status != HttpStatusCode.OK) {
        // Not an error worth surfacing: an event with no alliances yet, or a
        // demo event, is the normal case for most of a competition.
        log.info("frc.nexus {} for alliances of {}", response.status.value, eventKey)
        return null
    }

    val lookup = mutableMapOf<String, Int>()
    try {
        val root = Json.parseToJsonElement(response.bodyAsText()).jsonArray
        root.forEachIndexed { index, alliance ->
            val teams = alliance as? JsonArray ?: return@forEachIndexed
            for (team in teams) {
                val number = (team as? JsonPrimitive)?.contentOrNull ?: continue
                lookup[number] = index + 1
            }
        }
    } catch (e: Exception) {
        log.warn("Unparseable alliances for {}", eventKey, e)
        return null
    }

    allianceCache[eventKey] = CachedAlliances(lookup, now)
    return lookup
}

/**
 * Adds `redAlliance` / `blueAlliance` to playoff matches and returns the JSON.
 *
 * Works on a [JsonElement] rather than round-tripping through the typed `Event`
 * model **on purpose**. A typed round-trip would silently drop every key the
 * server doesn't model, `replayOf`, `actualCommitTime`, `announcements`,
 * `partsRequests`, and turn the proxy from lossless into a filter, so every
 * future Nexus field would need a server change before it could reach a client.
 * `ignoreUnknownKeys` on the client is only worth anything if the server passes
 * unknown keys through.
 *
 * Every failure path returns the body unchanged. A missing alliance number is a
 * cosmetic gap; a failed schedule is not.
 */
suspend fun enrichWithAlliances(body: String, eventKey: String, log: Logger): String {
    val root = try {
        Json.parseToJsonElement(body).jsonObject
    } catch (e: Exception) {
        log.warn("Event payload for {} was not a JSON object; passing through", eventKey, e)
        return body
    }

    val matches = root["matches"] as? JsonArray ?: return body

    // No playoff matches means no upstream call at all.
    if (matches.none { isPlayoff(it) }) return body

    val lookup = allianceLookup(eventKey, log) ?: return body
    if (lookup.isEmpty()) return body

    var changed = false
    val enriched = JsonArray(
        matches.map { element ->
            val match = element as? JsonObject ?: return@map element
            if (!isPlayoff(element)) return@map element

            val red = allianceOf(match["redTeams"], lookup)
            val blue = allianceOf(match["blueTeams"], lookup)
            if (red == null && blue == null) return@map element

            changed = true
            val updated = match.toMutableMap()
            if (red != null) updated["redAlliance"] = JsonPrimitive(red)
            if (blue != null) updated["blueAlliance"] = JsonPrimitive(blue)
            JsonObject(updated)
        }
    )

    if (!changed) return body

    val updatedRoot = root.toMutableMap()
    updatedRoot["matches"] = enriched
    return JsonObject(updatedRoot).toString()
}

private fun isPlayoff(element: JsonElement): Boolean {
    val obj = element as? JsonObject ?: return false
    val label = (obj["label"] as? JsonPrimitive)?.contentOrNull ?: return false
    return label.startsWith("Playoff") || label.startsWith("Final")
}

/**
 * Majority vote across the alliance rather than first hit.
 *
 * A backup robot substituted into a playoff match is not in the alliance's
 * `picks`, so one of the three or four teams can be unknown, and if a backup
 * came from another eliminated alliance, taking the first match would return
 * *that* alliance's number. Two agreeing teams outvote one stray.
 *
 * Returns null when the whole array is null, which Nexus does for a playoff
 * alliance that hasn't been decided. The client renders that as `A?`.
 */
private fun allianceOf(teams: JsonElement?, lookup: Map<String, Int>): Int? {
    val array = teams as? JsonArray ?: return null

    val votes = mutableListOf<Int>()
    for (team in array) {
        val number = (team as? JsonPrimitive)?.contentOrNull ?: continue
        lookup[number]?.let { votes.add(it) }
    }

    if (votes.isEmpty()) return null
    return votes.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
}
