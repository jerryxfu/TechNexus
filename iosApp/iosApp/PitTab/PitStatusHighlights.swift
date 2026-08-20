import ComposeApp
import SwiftUI

/// A team's live match status: what to call it, and what colour it is.
///
/// Carried together rather than as a bare colour so every surface can print the
/// label next to the swatch. `Style_iOS.md` is explicit that meaning must never
/// live in colour alone, and "blue vs purple" is exactly the distinction that
/// disappears for a colourblind user standing in a loud venue.
struct TeamStatus {
    let label: String

    /// Two-letter form, for the pit map and nothing else.
    ///
    /// A pit on `demo1815` is exactly 100 map units square, and "Queuing soon"
    /// measures about the same at the size a pit label is drawn — so it was
    /// clipped on both sides at every zoom level. Carried on the status rather
    /// than derived at the draw site, because the label strings are already
    /// shared vocabulary between here, `MatchStatusHelper` and
    /// `LiveActivityFormat`, and matching on them in a fourth place to pick an
    /// abbreviation is how the four drift apart.
    ///
    /// Everything with room to spell it out uses ``label``.
    let short: String

    let color: Color
}

/// Per-team colours derived from what each team's next match is doing right now.
///
/// Separate from `HighlightedTeamsStore`, which is a *preference*, the teams you chose to follow.
/// This is transient fact: who is on field, who is walking to the field, who should start packing up.
/// The two are shown together rather than one overriding the other, because they answer different questions and
/// you usually want both at once.
enum PitStatusHighlights {
    /// Statuses worth colouring, most urgent first. The index is the precedence.
    ///
    /// `label` is the display text `MatchStatusHelper` produces and the key this matches on;
    /// `short` is the pit-map abbreviation; `raw` is the Nexus status the label was resolved *from*, needed only to ask
    /// `MatchStatusHelper` for the colour when building [legend].
    ///
    /// **"Done" is deliberately absent.** A team is done with most of its matches for most of an event,
    /// so including it would paint the entire map grey by the middle of day two and drown out the four statuses that actually mean
    /// something. If you ever want it back, appending a row here is the whole change, but note it also lengthens the map legend by one.
    static let ranked: [(label: String, short: String, raw: String)] = [
        ("On field", "OF", "on field"),
        ("On deck", "OD", "on deck"),
        ("Now queuing", "NQ", "now queuing"),
        ("Queuing soon", "QS", "queuing soon"),
    ]

    /// The pit map's legend: code, spelled-out label, and colour, for all four statuses regardless of which are live right now.
    ///
    /// Colour comes back out of `MatchStatusHelper` rather than being listed above,
    /// because that function is already one of two places the status palette lives and a third copy is exactly
    /// the failure `CLAUDE.md` describes. It keys on the *raw* Nexus status, which is why [ranked] carries one.
    static var legend: [(short: String, label: String, color: Color)] {
        ranked.map { entry in
            (
                entry.short,
                entry.label,
                // `display` resolves a raw "on field" to Done/grey unless the match is actually playing, and the legend wants the green.
                MatchStatusHelper.display(
                    for: entry.raw,
                    isCurrentlyPlaying: entry.raw == "on field"
                ).color
            )
        }
    }

    /// Team number to status colour.
    ///
    /// Keyed on the **display label** from `MatchStatusHelper`, not on `match.status`.
    /// That matters: Nexus leaves a finished match reading `"on field"` until the score is committed,
    /// and the helper is the thing that resolves it to "Done". Switching on the raw status would light up
    /// every already-played match in green.
    /// A team can appear in two live matches at once, on deck for one and queuing soon for the next, so the more urgent status wins.
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

            guard
                let rank = ranked.firstIndex(where: { $0.label == display.text })
            else { continue }

            // The one time check, and it lives in `MatchStatusHelper` so the schedule cards apply the identical horizon.
            // Without it "Queuing soon" is effectively the default for any match not yet playing.
            if MatchStatusHelper.isFarFromQueuing(match) { continue }
            guard hasTrustedQueueTime(match, labelled: display.text) else { continue }

            // Nexus nulls the whole team array for an undecided playoff alliance, and individual entries for a no-show.
            // The array also arrives as `[Any]`, Kotlin's `List<String?>` loses its element type through ObjC,
            // which is why `MatchCardView` and `ScheduleLiveActivityManager` both cast the same way.
            let teams = (match.redTeams ?? []) + (match.blueTeams ?? [])
            for entry in teams {
                // `continue`, not the `"N/A"` those two substitute: a
                // placeholder here would become a highlighted team that doesn't
                // exist.
                guard let team = entry as? String else { continue }
                if let existing = bestRank[team], existing <= rank { continue }
                bestRank[team] = rank
                result[team] = TeamStatus(
                    label: display.text,
                    short: ranked[rank].short,
                    color: display.color
                )
            }
        }

        return result
    }

    /// Whether a match's status is trustworthy enough to colour a pit by.
    ///
    /// Deliberately **not** a time check. `MatchStatusHelper.isFarFromQueuing` owns that, for this and for the schedule cards.
    ///
    /// What this drops is a "Queuing soon" match carrying no `queueTime` at all.
    /// `isFarFromQueuing` falls back to `startTime` for those and waves them through, but we genuinely can't say
    /// how far out they are, and assuming "soon" is what produced the wall of purple in the first place.
    private static func hasTrustedQueueTime(
        _ match: Match,
        labelled label: String
    ) -> Bool {
        guard label == "Queuing soon" else { return true }
        return match.times.queueTime != nil
    }
}
