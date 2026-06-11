package net.jerryxf.technexus.statbotics

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn
import kotlin.time.Clock

class StatsViewModel : ViewModel() {
    private val repository by lazy {
        StatboticsRepository(scope = viewModelScope)
    }

    private val _teamQuery = MutableStateFlow("")
    val teamQuery: StateFlow<String> = _teamQuery

    private val _selectedYear = MutableStateFlow(currentYear())
    val selectedYear: StateFlow<Int> = _selectedYear

    private val _selectedEvent = MutableStateFlow<StatboticsTeamEvent?>(null)
    val selectedEvent: StateFlow<StatboticsTeamEvent?> = _selectedEvent


    val teamYearState get() = repository.teamYearState
    val teamEventsState get() = repository.teamEventsState
    val matchesState get() = repository.matchesState
    val yearState get() = repository.yearState




    val uiState: StateFlow<StatsUiState> by lazy {
        combine(
            repository.teamYearState,
            repository.teamEventsState,
            repository.matchesState,
            repository.yearState,
            _selectedEvent,
        ) { teamYear, events, matches, year, selectedEvent ->
            StatsUiState(
                teamYear = teamYear,
                events = events,
                matches = matches,
                year = year,
                selectedEvent = selectedEvent,
                epaLabel = epaLabel(teamYear, year),
                matchSummaries = matchSummaries(matches),
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = StatsUiState(),
        )
    }

    fun onQueryChange(query: String) {
        _teamQuery.value = query
    }

    fun onYearChange(year: Int) {
        _selectedYear.value = year
    }

    /** Called when user taps Search or hits the keyboard action. */
    fun onSearch() {
        val teamNumber = _teamQuery.value.trim().toIntOrNull() ?: return
        val year = _selectedYear.value
        repository.reset()
        _selectedEvent.value = null
        repository.loadTeamYear(teamNumber, year)
        repository.loadTeamEvents(teamNumber, year)
        repository.loadYear(year)
    }

    /** Called when user taps an event row. */
    fun onEventSelected(event: StatboticsTeamEvent) {
        _selectedEvent.value = event
        repository.loadEventMatches(event.eventKey)
    }

    /** Called when user navigates back from the match list. */
    fun onEventDismissed() {
        _selectedEvent.value = null
    }

    private fun epaLabel(
        teamYear: StatboticsState<StatboticsTeamYear>,
        year: StatboticsState<StatboticsYear>,
    ): String? {
        val ty = (teamYear as? StatboticsState.Success)?.data ?: return null
        val y  = (year as? StatboticsState.Success)?.data ?: return null
        return interpretEpa(ty.normEpa.current, y)
    }

    private fun matchSummaries(
        matchesState: StatboticsState<List<StatboticsMatch>>,
    ): List<MatchSummary> {
        val matches = (matchesState as? StatboticsState.Success)?.data ?: return emptyList()
        return matches.map { match ->
            val prediction = repository.predictMatch(match)
            MatchSummary(
                match            = match,
                prediction       = prediction,
                isPlayed         = match.redScore != null && match.blueScore != null,
                predictedCorrectly = when {
                    match.winner == null || prediction == null -> null
                    else -> prediction.predictedWinner == match.winner
                },
            )
        }
    }

    private fun currentYear(): Int = Clock.System.todayIn(
        TimeZone.currentSystemDefault()
    ).year
}

// ─── UI state ─────────────────────────────────────────────────────────────────

data class StatsUiState(
    val teamYear: StatboticsState<StatboticsTeamYear> = StatboticsState.Idle,
    val events: StatboticsState<List<StatboticsTeamEvent>> = StatboticsState.Idle,
    val matches: StatboticsState<List<StatboticsMatch>> = StatboticsState.Idle,
    val year: StatboticsState<StatboticsYear> = StatboticsState.Idle,
    val selectedEvent: StatboticsTeamEvent?                 = null,
    val epaLabel: String?                                   = null,
    val matchSummaries: List<MatchSummary>                  = emptyList(),
)

// ─── Match summary (match + prediction bundled) ───────────────────────────────

data class MatchSummary(
    val match: StatboticsMatch,
    val prediction: MatchPrediction?,
    val isPlayed: Boolean,
    val predictedCorrectly: Boolean?,   // null = not played yet
)