import ComposeApp
import SwiftUI

enum MatchStatusHelper {
    /// A match is "done" when:
    /// - Its score has been committed, OR
    /// - Its status is "On field", AND
    ///   - Another "On field" match has a later start time, OR
    ///   - Its estimated start time + buffer is in the past
    static func isDone(
        _ match: Match,
        currentOnFieldStart: Int64?
    ) -> Bool {
        // Nexus records actualCommitTime when the score is posted, which is the
        // only definitive end-of-match signal it gives us. Checked first and
        // independently of status: a committed match is over regardless of what
        // the queuing status still says.
        if match.times.isFinished { return true }

        guard match.status.lowercased() == "on field" else { return false }

        // Superseded by a newer "On field" match
        if let currentStart = currentOnFieldStart,
            match.times.startTime < currentStart
        {
            return true
        }

        // Match start + buffer is in the past. A heuristic, and only reached
        // when the event hasn't committed a score yet.
        let matchDurationBufferMs: Int64 = 3 * 60 * 1000
        let estimatedEnd = match.times.startTime + matchDurationBufferMs
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return nowMs > estimatedEnd
    }

    /// The "current" on-field start time aka the latest start time among "On field" matches.
    static func currentOnFieldStart(in matches: [Match]) -> Int64? {
        matches
            .filter { $0.status.lowercased() == "on field" }
            .map { $0.times.startTime }
            .max()
    }

    /// The match currently being played (if any).
    static func isCurrentlyPlaying(
        _ match: Match,
        currentOnFieldStart: Int64?
    ) -> Bool {
        match.status.lowercased() == "on field"
            && match.times.startTime == currentOnFieldStart
            && !isDone(match, currentOnFieldStart: currentOnFieldStart)
    }

    /// The match the UI should lead with.
    ///
    /// - Parameter skippingFinished: when true, an "On field" match that has
    ///   already finished is ignored and the next queuing match is returned
    ///   instead. The Live Activity wants that, so the lock screen looks
    ///   forward; the header does not, so it can still report "Done".
    static func latestMatch(
        in event: Event,
        skippingFinished: Bool = false
    ) -> Match? {
        let currentStart = currentOnFieldStart(in: event.matches)

        if skippingFinished {
            if let playing = event.matches.first(where: {
                isCurrentlyPlaying($0, currentOnFieldStart: currentStart)
            }) {
                return playing
            }
        } else if let currentOnField =
            event.matches
            .filter({ $0.status.lowercased() == "on field" })
            .max(by: { $0.times.startTime < $1.times.startTime })
        {
            return currentOnField
        }

        for status in ["on deck", "now queuing", "queuing soon"] {
            if let match = event.matches.first(where: {
                $0.status.lowercased() == status
            }) {
                return match
            }
        }

        return nil
    }

    /// How far ahead of its queue time a match starts being worth reporting.
    ///
    /// Hoisted out of `MatchCardView`, which had this inline, because the pit map needs the identical horizon.
    /// Without it "Queuing soon" is effectively the default for any match not yet playing. Keeping things consistent.
    static let queuingHorizonMs: Int64 = 15 * 60 * 1000

    /// True when a match is far enough out that its queuing status isn't yet worth showing.
    // Falls back to start time when queue time is unknown.
    static func isFarFromQueuing(_ match: Match) -> Bool {
        let queueTimeMs = match.times.queueTime?.int64Value ?? match.times.startTime
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return (queueTimeMs - nowMs) > queuingHorizonMs
    }

    /// Canonical label, colour and icon for a status. Every iOS surface reads from here so they can't drift apart.
    static func display(
        for status: String,
        isCurrentlyPlaying: Bool = false
    ) -> (text: String, color: Color, icon: String) {
        if isCurrentlyPlaying {
            return ("On field", .green, "flag.fill")
        }
        switch status.lowercased() {
        case "on field":
            return ("Done", .gray, "checkmark.circle.fill")
        case "on deck":
            return ("On deck", .blue, "clock.fill")
        case "now queuing":
            return ("Now queuing", .orange, "figure.walk")
        case "queuing soon":
            return ("Queuing soon", .purple, "hourglass")
        default:
            return (status, .secondary, "circle")
        }
    }

    /// Convenience for callers that have the whole event to hand.
    static func display(
        for match: Match,
        in event: Event
    ) -> (text: String, color: Color, icon: String) {
        let currentStart = currentOnFieldStart(in: event.matches)
        return display(
            for: match.status,
            isCurrentlyPlaying: isCurrentlyPlaying(
                match,
                currentOnFieldStart: currentStart
            )
        )
    }

    // MARK: - Alliance labels

    /// What to call an alliance on this match.
    ///
    /// `RED` / `BLUE` in practice and qualifications, where the field side is
    /// the only thing that identifies an alliance. `A3` in playoffs, where the
    /// seed is what people actually say out loud — and `A?` when it's a playoff
    /// match whose alliance isn't decided yet.
    ///
    /// There is deliberately no fall back to `RED` during playoffs. Nexus
    /// returns the entire team array as null for an undecided playoff alliance,
    /// so at that point we know neither the seed nor the teams; showing `RED`
    /// would be answering a question nobody asked with the one fact that isn't
    /// in doubt.
    static func allianceLabel(for match: Match, isRed: Bool) -> String {
        guard match.isPlayoff else { return isRed ? "RED" : "BLUE" }
        guard let seed = (isRed ? match.redAlliance : match.blueAlliance)
        else { return "A?" }
        return "A\(seed.intValue)"
    }
}
