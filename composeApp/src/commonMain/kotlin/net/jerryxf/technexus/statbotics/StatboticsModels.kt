package net.jerryxf.technexus.statbotics

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class Alliance { RED, BLUE }

@Serializable
data class EpaStats(
    val total: Double,
    val auto: Double,
    val teleop: Double,
    val endgame: Double,
)

@Serializable
data class NormEpa(
    val current: Double,
    val recent: Double,
    val mean: Double,
    val max: Double,
)

@Serializable
data class WinRecord(
    val wins: Int,
    val losses: Int,
    val ties: Int,
    val count: Int,
    val winrate: Double,
)

@Serializable
data class StatboticsTeam(
    val team: Int,
    val name: String,
    val country: String? = null,
    val state: String? = null,
    val district: String? = null,
    @SerialName("rookie_year") val rookieYear: Int,
    val active: Boolean,
    val record: WinRecord,
    @SerialName("norm_epa") val normEpa: NormEpa,
)

@Serializable
data class StatboticsTeamYear(
    val team: Int,
    val year: Int,
    val name: String,
    val record: WinRecord,
    val epa: EpaStats,
    @SerialName("norm_epa") val normEpa: NormEpa,
    @SerialName("ranking_points") val rankingPoints: Double? = null,
    @SerialName("unitless_epa") val unitlessEpa: Double,
)

@Serializable
data class StatboticsEvent(
    val key: String,
    val year: Int,
    val name: String,
    val country: String? = null,
    val state: String? = null,
    val district: String? = null,
    val teams: Int,
)

@Serializable
data class StatboticsTeamEvent(
    val team: Int,
    val year: Int,
    @SerialName("event") val eventKey: String,
    @SerialName("event_name") val eventName: String,
    val record: WinRecord,
    val rank: Int? = null,
    val epa: EpaStats,
    @SerialName("norm_epa") val normEpa: Double? = null,
)

@Serializable
data class StatboticsMatch(
    val key: String,
    val year: Int,
    @SerialName("event") val eventKey: String,
    @SerialName("comp_level") val compLevel: String,
    @SerialName("set_number") val setNumber: Int,
    @SerialName("match_number") val matchNumber: Int,
    @SerialName("red_teams") val redTeams: List<Int>,
    @SerialName("blue_teams") val blueTeams: List<Int>,
    @SerialName("red_score") val redScore: Int? = null,
    @SerialName("blue_score") val blueScore: Int? = null,
    val winner: Alliance? = null,
    @SerialName("red_epa_sum") val redEpaSum: Double? = null,
    @SerialName("blue_epa_sum") val blueEpaSum: Double? = null,
    @SerialName("predicted_winner") val predictedWinner: Alliance? = null,
    @SerialName("win_prob") val winProb: Double? = null,
)

@Serializable
data class MatchPrediction(
    val matchKey: String,
    val predictedWinner: Alliance,
    val redWinProb: Double,
    val blueWinProb: Double,
    val redEpaSum: Double,
    val blueEpaSum: Double,
)

@Serializable
data class StatboticsYear(
    val year: Int,
    @SerialName("epa_mean") val epaMean: Double,
    @SerialName("epa_std") val epaStd: Double,
    @SerialName("epa_max") val epaMax: Double,
    val dominance: Double? = null,
    @SerialName("num_teams") val numTeams: Int,
    @SerialName("num_events") val numEvents: Int,
    @SerialName("num_matches") val numMatches: Int,
)

sealed class StatboticsError : Exception() {
    data class NetworkError(override val message: String) : StatboticsError()
    data class NotFound(val resource: String) : StatboticsError()
    data class ParseError(override val cause: Throwable) : StatboticsError()
    data object RateLimited : StatboticsError()
}
