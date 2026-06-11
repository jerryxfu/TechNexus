package net.jerryxf.technexus.statbotics

import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import net.jerryxf.technexus.client

class StatboticsClient(
    private val baseUrl: String = BASE_URL,
) {
    companion object {
        const val BASE_URL = "https://api.statbotics.io/v3"
    }

    private suspend inline fun <reified T> get(
        path: String,
        params: Map<String, String> = emptyMap(),
    ): T {
        val response = client.get("$baseUrl$path") {
            params.forEach { (k, v) -> parameter(k, v) }
        }
        return when (response.status) {
            HttpStatusCode.OK -> response.body<T>()
            HttpStatusCode.NotFound -> throw StatboticsError.NotFound(path)
            HttpStatusCode.TooManyRequests -> throw StatboticsError.RateLimited
            else -> throw StatboticsError.NetworkError("HTTP ${response.status.value} for $path")
        }
    }

    suspend fun getTeam(teamNumber: Int): StatboticsTeam =
        get("/team/$teamNumber")

    suspend fun getTeams(
        country: String? = null,
        state: String? = null,
        district: String? = null,
        activeOnly: Boolean = true,
        metric: String = "norm_epa",
        limit: Int = 100,
        offset: Int = 0,
    ): List<StatboticsTeam> = get(
        "/teams",
        buildParams(
            "country" to country,
            "state" to state,
            "district" to district,
            "active" to if (activeOnly) "true" else null,
            "metric" to metric,
            "limit" to "$limit",
            "offset" to "$offset",
        )
    )

    suspend fun getTeamYear(teamNumber: Int, year: Int): StatboticsTeamYear =
        get("/team_year/$teamNumber/$year")

    suspend fun getTeamYears(
        teamNumber: Int? = null,
        year: Int? = null,
        metric: String = "norm_epa",
        limit: Int = 100,
        offset: Int = 0,
    ): List<StatboticsTeamYear> = get(
        "/team_years",
        buildParams(
            "team" to teamNumber?.toString(),
            "year" to year?.toString(),
            "metric" to metric,
            "limit" to "$limit",
            "offset" to "$offset",
        )
    )

    suspend fun getEvent(eventKey: String): StatboticsEvent =
        get("/event/$eventKey")

    suspend fun getEvents(
        year: Int? = null,
        country: String? = null,
        state: String? = null,
        district: String? = null,
        type: String? = null,
        week: Int? = null,
        limit: Int = 100,
        offset: Int = 0,
    ): List<StatboticsEvent> = get(
        "/events",
        buildParams(
            "year" to year?.toString(),
            "country" to country,
            "state" to state,
            "district" to district,
            "type" to type,
            "week" to week?.toString(),
            "limit" to "$limit",
            "offset" to "$offset",
        )
    )

    suspend fun getTeamEvent(teamNumber: Int, eventKey: String): StatboticsTeamEvent =
        get("/team_event/$teamNumber/$eventKey")

    suspend fun getTeamEvents(
        teamNumber: Int? = null,
        eventKey: String? = null,
        year: Int? = null,
        metric: String = "norm_epa",
        limit: Int = 100,
        offset: Int = 0,
    ): List<StatboticsTeamEvent> = get(
        "/team_events",
        buildParams(
            "team" to teamNumber?.toString(),
            "event" to eventKey,
            "year" to year?.toString(),
            "metric" to metric,
            "limit" to "$limit",
            "offset" to "$offset",
        )
    )

    suspend fun getMatch(matchKey: String): StatboticsMatch =
        get("/match/$matchKey")

    suspend fun getMatches(
        teamNumber: Int? = null,
        eventKey: String? = null,
        year: Int? = null,
        compLevel: String? = null,
        limit: Int = 100,
        offset: Int = 0,
    ): List<StatboticsMatch> = get(
        "/matches",
        buildParams(
            "team" to teamNumber?.toString(),
            "event" to eventKey,
            "year" to year?.toString(),
            "comp_level" to compLevel,
            "limit" to "$limit",
            "offset" to "$offset",
        )
    )

    suspend fun getYear(year: Int): StatboticsYear =
        get("/year/$year")

    suspend fun getYears(): List<StatboticsYear> =
        get("/years")

    private fun buildParams(vararg pairs: Pair<String, String?>): Map<String, String> =
        pairs.filter { it.second != null }.associate { it.first to it.second!! }
}