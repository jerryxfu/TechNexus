import ComposeApp
import SwiftUI

/// Per-team colours derived from what each team's next match is doing right now.
///
/// Separate from `HighlightedTeamsStore`, which is a *preference* — the teams you
/// chose to follow. This is transient fact: who is on field, who is walking to
/// the field, who should start packing up. The two are shown together rather
/// than one overriding the other, because they answer different questions and
/// you usually want both at once.
/// A team's live match status: what to call it, and what colour it is.
///
/// Carried together rather than as a bare colour so every surface can print the
/// label next to the swatch. `Style_iOS.md` is explicit that meaning must never
/// live in colour alone, and "blue vs purple" is exactly the distinction that
/// disappears for a colourblind user standing in a loud venue.
struct TeamStatus {
    let label: String
    let color: Color
}

enum PitStatusHighlights {
    /// Statuses worth colouring, most urgent first. The index is the precedence.
    ///
    /// **"Done" is deliberately absent.** A team is done with most of its matches
    /// for most of an event, so including it would paint the entire map grey by
    /// the middle of day two and drown out the four statuses that actually mean
    /// something. If you ever want it back, adding `"Done"` to the end of this
    /// array is the whole change.
    private static let ranked = ["On field", "On deck", "Now queuing", "Queuing soon"]

    /// Team number to status colour.
    ///
    /// Keyed on the **display label** from `MatchStatusHelper`, not on
    /// `match.status`. That matters: Nexus leaves a finished match reading
    /// `"on field"` until the score is committed, and the helper is the thing
    /// that resolves it to "Done". Switching on the raw status would light up
    /// every already-played match in green.
    ///
    /// A team can legitimately appear in two live matches at once — on deck for
    /// one and queuing soon for the next — so the more urgent status wins.
    static func derive(from event: Event) -> [String: TeamStatus] {
        let currentOnFieldStart = MatchStatusHelper.currentOnFieldStart(
            in: event.matches
        )

        var result: [String: TeamStatus] = [:]
        var bestRank: [String: Int] = [:]

        for match in event.matches {
            let display = MatchStatusHelper.display(
                for: match.status,
                isCurrentlyPlaying: MatchStatusHelper.isCurrentlyPlaying(
                    match,
                    currentOnFieldStart: currentOnFieldStart
                )
            )

            guard let rank = ranked.firstIndex(of: display.text) else { continue }

            // Nexus nulls the whole team array for an undecided playoff
            // alliance, and individual entries for a no-show. The array also
            // arrives as `[Any]` — Kotlin's `List<String?>` loses its element
            // type through ObjC, which is why `MatchCardView` and
            // `ScheduleLiveActivityManager` both cast the same way.
            let teams = (match.redTeams ?? []) + (match.blueTeams ?? [])
            for entry in teams {
                // `continue`, not the `"N/A"` those two substitute: a
                // placeholder here would become a highlighted team that doesn't
                // exist.
                guard let team = entry as? String else { continue }
                if let existing = bestRank[team], existing <= rank { continue }
                bestRank[team] = rank
                result[team] = TeamStatus(label: display.text, color: display.color)
            }
        }

        return result
    }
}
