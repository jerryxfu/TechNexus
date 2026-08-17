package net.jerryxf.technexus.shared

import kotlin.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

val jsonConfig = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

@Serializable
data class Event(
    val eventKey: String,
    val dataAsOfTime: Long,
    /**
     * The match Nexus itself considers currently queuing, e.g. "Practice 10".
     * Authoritative, unlike anything the clients reconstruct from [matches].
     */
    val nowQueuing: String? = null,
    val matches: List<Match>
)

@Serializable
data class Match(
    val label: String,
    val status: String,
    val breakAfter: String?,
    val redTeams: List<String?>?,
    val blueTeams: List<String?>?,
    val times: MatchTimes
)

/**
 * Match timing, in epoch milliseconds.
 *
 * The `estimated*` values are predictions and move as the event runs. The
 * `actual*` values are recorded when a transition really happened and are null
 * until then, which makes them the reliable basis for "did this match change
 * state" — far better than diffing [Match.status] strings.
 */
@Serializable
data class MatchTimes(
    val estimatedQueueTime: Long?,
    val estimatedOnDeckTime: Long?,
    val estimatedOnFieldTime: Long,
    val estimatedStartTime: Long,
    val actualQueueTime: Long? = null,
    val actualOnDeckTime: Long? = null,
    val actualOnFieldTime: Long? = null
)

/**
 * One entry from `GET /events`, which Nexus returns as a map of event key to
 * these fields. Nexus purges past seasons, so every event here is current or
 * upcoming.
 */
@Serializable
data class NexusEvent(
    val name: String,
    val start: Long,
    val end: Long
)

/**
 * [NexusEvent] with its key folded in, so the list can be passed around and
 * displayed without carrying the map. Flattened in Kotlin rather than Swift
 * because Kotlin maps bridge awkwardly to Swift dictionaries.
 */
@Serializable
data class EventSummary(
    val key: String,
    val name: String,
    val start: Long,
    val end: Long
)

@Serializable
data class MatchScore(
    val blue: UShort,
    val red: UShort
)

@Serializable
data class Battery(
    val id: UInt,
    val name: String,
    val type: String,
    val year: UByte
)

@Serializable
data class BatteryCycle(
    val id: UInt,
    val batteryId: UInt,
    val startTime: Instant,
    val endTime: Instant
)
