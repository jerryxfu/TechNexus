package net.jerryxf.technexus

import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import net.jerryxf.technexus.shared.*

private const val apiUrl = "https://nexus.raphdf201.net"

/**
 * Every current and upcoming event on Nexus, soonest first.
 *
 * Throws on failure rather than returning null. [getEventData] and the battery
 * calls below swallow their exceptions, which is why every Swift caller needs a
 * comment explaining that its `catch` is dead code — don't copy that here.
 */
suspend fun getEvents(): List<EventSummary> =
    client.get("$apiUrl/events")
        .body<Map<String, NexusEvent>>()
        .map { (key, event) -> EventSummary(key, event.name, event.start, event.end) }
        .sortedBy { it.start }

suspend fun getEventData(eventKey: String): Event? {
    return try {
        client.get("$apiUrl/event/$eventKey").body<Event>()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

suspend fun getMatchScore(event: String, match: MatchId): MatchScore? {
    val matchId = match.type.short + match.number

    return try {
        client.get("$apiUrl/event/$event/match/$matchId").body()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

/**
 * Create a battery. Returns the battery's id.
 *
 * It doesn't care of the id you input initially
 */
suspend fun createBattery(bat: Battery): UInt? {
    return try {
        client.post("$apiUrl/batteries/new") {
            setBody(bat)
        }.body()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

suspend fun getBatteries(): List<Battery> {
    return try {
        client.get("$apiUrl/batteries/all").body()
    } catch (e: Exception) {
        e.printStackTrace()
        emptyList()
    }
}

suspend fun getBattery(id: UInt): Battery? {
    return try {
        client.get("$apiUrl/batteries/$id").body()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

suspend fun updateBattery(bat: Battery): Boolean {
    return try {
        client.put("$apiUrl/batteries/edit") {
            setBody(bat)
        }.status == HttpStatusCode.OK
    } catch (e: Exception) {
        e.printStackTrace()
        false
    }
}

suspend fun deleteBattery(bat: Battery): Boolean {
    return try {
        client.delete("$apiUrl/batteries/${bat.id}").status == HttpStatusCode.OK
    } catch (e: Exception) {
        e.printStackTrace()
        false
    }
}

/**
 * Create a cycle. Returns the created cycle.
 *
 * It ignores the ID you provide initially.
 */
suspend fun createCycle(cycle: BatteryCycle): UInt? {
    return try {
        client.post("$apiUrl/cycles/new") {
            setBody(cycle)
        }.body()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

suspend fun getCycles(): List<BatteryCycle> {
    return try {
        client.get("$apiUrl/cycles/all").body()
    } catch (e: Exception) {
        e.printStackTrace()
        emptyList()
    }
}

suspend fun getCycle(id: UInt): BatteryCycle? {
    return try {
        client.get("$apiUrl/cycles/$id").body()
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

suspend fun updateCycle(cycle: BatteryCycle): Boolean {
    return try {
        client.put("$apiUrl/cycles/edit") {
            setBody(cycle)
        }.status == HttpStatusCode.OK
    } catch (e: Exception) {
        e.printStackTrace()
        false
    }
}

suspend fun deleteCycle(cycle: BatteryCycle): Boolean {
    return try {
        client.delete("$apiUrl/cycles/${cycle.id}").status == HttpStatusCode.OK
    } catch (e: Exception) {
        e.printStackTrace()
        false
    }
}
