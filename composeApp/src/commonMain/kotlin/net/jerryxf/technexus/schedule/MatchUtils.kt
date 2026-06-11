package net.jerryxf.technexus.schedule

import net.jerryxf.technexus.shared.Event
import net.jerryxf.technexus.shared.Match
import kotlin.collections.iterator

fun getPlayoffAlliance(match: Match, event: Event): String? {
    fun matchByNumber(num: Int): Match? =
        event.matches.find { it.label == "Playoff $num" }

    fun resolveAlliance(matchNum: Int, isRed: Boolean): String? {
        val m = matchByNumber(matchNum)

        // If the match has teams assigned, just read directly from it
        val teams = if (isRed) m?.redTeams else m?.blueTeams
        if (!teams.isNullOrEmpty() && teams.any { it != null }) {
            return if (isRed) "R$matchNum" else "B$matchNum" // placeholder, see below
        }

        return when (matchNum) {
            1 -> if (isRed) "A1" else "A8"
            2 -> if (isRed) "A4" else "A5"
            3 -> if (isRed) "A2" else "A7"
            4 -> if (isRed) "A3" else "A6"
            5 -> if (isRed) resolveFromTeams(matchByNumber(1), won = false, event)
            else resolveFromTeams(matchByNumber(2), won = false, event)

            6 -> if (isRed) resolveFromTeams(matchByNumber(3), won = false, event)
            else resolveFromTeams(matchByNumber(4), won = false, event)

            7 -> if (isRed) resolveFromTeams(matchByNumber(1), won = true, event)
            else resolveFromTeams(matchByNumber(2), won = true, event)

            8 -> if (isRed) resolveFromTeams(matchByNumber(3), won = true, event)
            else resolveFromTeams(matchByNumber(4), won = true, event)

            9 -> if (isRed) resolveFromTeams(matchByNumber(7), won = false, event)
            else resolveFromTeams(matchByNumber(6), won = true, event)

            10 -> if (isRed) resolveFromTeams(matchByNumber(8), won = false, event)
            else resolveFromTeams(matchByNumber(5), won = true, event)

            11 -> if (isRed) resolveFromTeams(matchByNumber(7), won = true, event)
            else resolveFromTeams(matchByNumber(8), won = true, event)

            12 -> if (isRed) resolveFromTeams(matchByNumber(10), won = true, event)
            else resolveFromTeams(matchByNumber(9), won = true, event)

            13 -> if (isRed) resolveFromTeams(matchByNumber(11), won = false, event)
            else resolveFromTeams(matchByNumber(12), won = true, event)

            14 -> if (isRed) resolveFromTeams(matchByNumber(11), won = true, event)
            else resolveFromTeams(matchByNumber(13), won = true, event)

            else -> null
        }
    }

    val matchNumber = when {
        match.label.startsWith("Final") -> 14
        match.label.startsWith("Playoff") ->
            match.label.removePrefix("Playoff").trim().toIntOrNull() ?: return null

        else -> return null
    }

    val redAlliance = resolveAlliance(matchNumber, isRed = true) ?: return null
    val blueAlliance = resolveAlliance(matchNumber, isRed = false) ?: return null
    return "$redAlliance vs $blueAlliance"
}

// Given a match, find which alliance (A1-A8) won or lost it
private fun resolveFromTeams(match: Match?, won: Boolean, event: Event): String? {
    if (match == null) return null

    val matchNum = match.label.removePrefix("Playoff").trim().toIntOrNull() ?: return null

    // Determine winner by checking which alliance's teams appear in the next match
    // We do this by recursively checking: whichever team list from this match
    // shows up in a later match as red or blue is the winner
    val redTeams = match.redTeams?.filterNotNull() ?: emptyList()
    val blueTeams = match.blueTeams?.filterNotNull() ?: emptyList()

    // Find the next match that contains teams from this match
    val nextMatches = event.matches.filter { m ->
        val num = m.label.removePrefix("Playoff").trim().toIntOrNull() ?: return@filter false
        num > matchNum
    }

    for (next in nextMatches.sortedBy {
        it.label.removePrefix("Playoff").trim().toIntOrNull() ?: 99
    }) {
        val nextRed = next.redTeams?.filterNotNull() ?: emptyList()
        val nextBlue = next.blueTeams?.filterNotNull() ?: emptyList()

        val redWon = nextRed.any { it in redTeams } || nextBlue.any { it in redTeams }
        val blueWon = nextRed.any { it in blueTeams } || nextBlue.any { it in blueTeams }

        if (redWon && !blueWon) return if (won) getAllianceForTeams(redTeams, event)
        else getAllianceForTeams(blueTeams, event)
        if (blueWon && !redWon) return if (won) getAllianceForTeams(blueTeams, event)
        else getAllianceForTeams(redTeams, event)
    }

    return null // match not yet resolved
}

// Find which A1-A8 alliance a team belongs to by looking at Round 1 matches
private fun getAllianceForTeams(teams: List<String>, event: Event): String? {
    val round1 = mapOf(
        "Playoff 1" to ("A1" to "A8"),
        "Playoff 2" to ("A4" to "A5"),
        "Playoff 3" to ("A2" to "A7"),
        "Playoff 4" to ("A3" to "A6"),
    )

    for ((label, alliances) in round1) {
        val m = event.matches.find { it.label == label } ?: continue
        val redTeams = m.redTeams?.filterNotNull() ?: emptyList()
        val blueTeams = m.blueTeams?.filterNotNull() ?: emptyList()
        if (teams.any { it in redTeams }) return alliances.first
        if (teams.any { it in blueTeams }) return alliances.second
    }

    return null
}
