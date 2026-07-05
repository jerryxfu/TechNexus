package net.jerryxf.technexus.statbotics

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlin.math.exp

class StatboticsRepository(
    private val scope: CoroutineScope,
    private val client: StatboticsClient = StatboticsClient(),
) {

    private val _teamYearState = MutableStateFlow<StatboticsState<StatboticsTeamYear>>(StatboticsState.Idle)
    val teamYearState: StateFlow<StatboticsState<StatboticsTeamYear>> = _teamYearState

    private val _teamEventsState = MutableStateFlow<StatboticsState<List<StatboticsTeamEvent>>>(StatboticsState.Idle)
    val teamEventsState: StateFlow<StatboticsState<List<StatboticsTeamEvent>>> = _teamEventsState

    private val _matchesState = MutableStateFlow<StatboticsState<List<StatboticsMatch>>>(StatboticsState.Idle)
    val matchesState: StateFlow<StatboticsState<List<StatboticsMatch>>> = _matchesState

    private val _yearState = MutableStateFlow<StatboticsState<StatboticsYear>>(StatboticsState.Idle)
    val yearState: StateFlow<StatboticsState<StatboticsYear>> = _yearState

    private val teamYearCache = mutableMapOf<Pair<Int, Int>, StatboticsTeamYear>()
    private val matchCache = mutableMapOf<String, List<StatboticsMatch>>()
    private val yearCache = mutableMapOf<Int, StatboticsYear>()


    fun loadTeamYear(teamNumber: Int, year: Int) {
        scope.launch {
            _teamYearState.value = StatboticsState.Loading
            _teamYearState.value = teamYearCache[teamNumber to year]
                ?.let { StatboticsState.Success(it) }
                ?: runCatching { client.getTeamYear(teamNumber, year) }
                    .onSuccess { teamYearCache[teamNumber to year] = it }
                    .fold(
                        onSuccess = { StatboticsState.Success(it) },
                        onFailure = { StatboticsState.Error(it.toStatboticsError()) },
                    )
        }
    }


    fun loadTeamEvents(teamNumber: Int, year: Int) {
        scope.launch {
            _teamEventsState.value = StatboticsState.Loading
            _teamEventsState.value = runCatching {
                client.getTeamEvents(teamNumber = teamNumber, year = year)
                    .sortedByDescending { it.eventKey }
            }.fold(
                onSuccess = { StatboticsState.Success(it) },
                onFailure = { StatboticsState.Error(it.toStatboticsError()) },
            )
        }
    }

    fun loadEventMatches(eventKey: String) {
        scope.launch {
            _matchesState.value = StatboticsState.Loading
            _matchesState.value = matchCache[eventKey]
                ?.let { StatboticsState.Success(it) }
                ?: runCatching {
                    client.getMatches(eventKey = eventKey, limit = 200)
                        .sortedWith(compareBy({ it.compLevel.order() }, { it.matchNumber }))
                }
                    .onSuccess { matchCache[eventKey] = it }
                    .fold(
                        onSuccess = { StatboticsState.Success(it) },
                        onFailure = { StatboticsState.Error(it.toStatboticsError()) },
                    )
        }
    }

    fun loadYear(year: Int) {
        scope.launch {
            _yearState.value = StatboticsState.Loading
            _yearState.value = yearCache[year]
                ?.let { StatboticsState.Success(it) }
                ?: runCatching { client.getYear(year) }
                    .onSuccess { yearCache[year] = it }
                    .fold(
                        onSuccess = { StatboticsState.Success(it) },
                        onFailure = { StatboticsState.Error(it.toStatboticsError()) },
                    )
        }
    }


    fun predictMatch(match: StatboticsMatch): MatchPrediction? {
        val redEpa = match.redEpaSum ?: return null
        val blueEpa = match.blueEpaSum ?: return null
        return computePrediction(match.key, redEpa, blueEpa)
    }

    fun reset() {
        teamYearCache.clear()
        matchCache.clear()
        yearCache.clear()
        _teamYearState.value = StatboticsState.Idle
        _teamEventsState.value = StatboticsState.Idle
        _matchesState.value = StatboticsState.Idle
        _yearState.value = StatboticsState.Idle
    }
}


fun computePrediction(
    matchKey: String,
    redEpa: Double,
    blueEpa: Double,
    k: Double = 0.35,
): MatchPrediction {
    val diff = redEpa - blueEpa
    val redWinProb = 1.0 / (1.0 + exp(-k * diff))
    val blueWinProb = 1.0 - redWinProb
    return MatchPrediction(
        matchKey = matchKey,
        predictedWinner = if (redWinProb >= 0.5) Alliance.RED else Alliance.BLUE,
        redWinProb = redWinProb,
        blueWinProb = blueWinProb,
        redEpaSum = redEpa,
        blueEpaSum = blueEpa,
    )
}


fun interpretEpa(normEpaCurrent: Double, year: StatboticsYear): String {
    val z = (normEpaCurrent - year.epaMean) / year.epaStd
    return when {
        z > 3.0  -> "Elite"
        z > 2.0  -> "Excellent"
        z > 1.0  -> "Strong"
        z > 0.0  -> "Above average"
        z > -1.0 -> "Below average"
        else     -> "Developing"
    }
}


sealed class StatboticsState<out T> {
    data object Idle : StatboticsState<Nothing>()
    data object Loading : StatboticsState<Nothing>()
    data class Success<T>(val data: T) : StatboticsState<T>()
    data class Error(val error: StatboticsError) : StatboticsState<Nothing>()
}

private fun Throwable.toStatboticsError(): StatboticsError = when (this) {
    is StatboticsError -> this
    else               -> StatboticsError.NetworkError(message ?: "Unknown error")
}

private fun String.order() = when (this) {
    "qm" -> 0
    "qf" -> 1
    "sf" -> 2
    "f"  -> 3
    else -> 4
}