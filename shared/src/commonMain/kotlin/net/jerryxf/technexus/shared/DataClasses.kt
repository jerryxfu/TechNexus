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
    val breakAfter: String? = null,
    val redTeams: List<String?>? = null,
    val blueTeams: List<String?>? = null,
    val times: MatchTimes,
    /**
     * The match this one replays, or null. Nexus labels these
     * `Qualification 24 Replay` and returns them in the same array as the
     * original, so without this a replay is indistinguishable from a duplicate.
     */
    val replayOf: String? = null,
    /**
     * Playoff alliance seed, 1-based. **Added by our server**, not by Nexus (see `Alliances.kt`).
     * Null outside playoffs, and null during playoffs when
     * alliance selection hasn't reached this match yet.
     *
     * Null does not mean "quals". Use [isPlayoff] to tell those apart: a playoff
     * match with a null alliance renders as `A?`, a qualification match renders
     * as `RED`.
     */
    val redAlliance: Int? = null,
    val blueAlliance: Int? = null
) {
    /**
     * Nexus labels are documented as `Practice N`, `Qualification N`,
     * `Qualification N Replay`, `Playoff N` and `Final N`, so the prefix is a
     * reliable discriminator and no parsing is needed.
     *
     * A member property rather than an extension, because extensions on classes
     * bridge awkwardly to Swift and this is read from SwiftUI.
     */
    val isPlayoff: Boolean
        get() = label.startsWith("Playoff") || label.startsWith("Final")
}

/**
 * Match timing, in epoch milliseconds.
 *
 * Every field is nullable, because every field is nullable in the Nexus schema.
 *
 * The `estimated*` values are predictions and move as the event runs. The
 * `actual*` values are recorded when a transition really happened and are null
 * until then, which makes them the reliable basis for "did this match change
 * state". Tar better than diffing [Match.status] strings.
 */
@Serializable
data class MatchTimes(
    /** Original schedule. Null for playoffs and when no schedule was published. */
    val scheduledStartTime: Long? = null,
    val estimatedQueueTime: Long? = null,
    val estimatedOnDeckTime: Long? = null,
    val estimatedOnFieldTime: Long? = null,
    val estimatedStartTime: Long? = null,
    val actualQueueTime: Long? = null,
    val actualOnDeckTime: Long? = null,
    val actualOnFieldTime: Long? = null,
    val actualStartTime: Long? = null,
    /**
     * When the score was committed. This is the only *definitive* "this match is
     * over" signal Nexus provides; everything else in the app currently infers it
     * from "estimated start plus three minutes is in the past".
     */
    val actualCommitTime: Long? = null
) {
    /**
     * Best available start time, for sorting and display.
     *
     * Falls back through the chain rather than forcing every call site to
     * unwrap, because a match with *no* timing at all is not a real case.
     * It would mean Nexus published a match with an empty `times` object.
     *
     * If that ever happens the value is `0`, which sorts the match to the top of
     * the list and makes [isFinished]-style checks treat it as long past, so it
     * lands in the collapsed "past matches" section. That is the least harmful
     * place for a match we know nothing about, but it *is* a fallback and not a
     * real time. Check [hasTiming] before presenting it as one.
     */
    val startTime: Long
        get() = estimatedStartTime
            ?: actualStartTime
            ?: estimatedOnFieldTime
            ?: actualOnFieldTime
            ?: scheduledStartTime
            ?: 0L

    val hasTiming: Boolean
        get() = estimatedStartTime != null
                || actualStartTime != null
                || estimatedOnFieldTime != null
                || actualOnFieldTime != null
                || scheduledStartTime != null

    /** Actual if it happened, estimate otherwise. Null if neither is known. */
    val queueTime: Long? get() = actualQueueTime ?: estimatedQueueTime
    val onDeckTime: Long? get() = actualOnDeckTime ?: estimatedOnDeckTime
    val onFieldTime: Long? get() = actualOnFieldTime ?: estimatedOnFieldTime

    /** Definitive, unlike the buffer heuristic in `MatchStatusHelper.isDone`. */
    val isFinished: Boolean get() = actualCommitTime != null
}

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
