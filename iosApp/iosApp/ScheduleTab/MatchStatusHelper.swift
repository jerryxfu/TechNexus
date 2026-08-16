import ComposeApp
import SwiftUI

enum MatchStatusHelper {
    /// A match is "done" when:
    /// - Its status is "On field", AND
    ///   - Another "On field" match has a later start time, OR
    ///   - Its estimated start time + buffer is in the past
    static func isDone(
        _ match: Match,
        currentOnFieldStart: Int64?
    ) -> Bool {
        guard match.status.lowercased() == "on field" else { return false }

        // Superseded by a newer "On field" match
        if let currentStart = currentOnFieldStart,
            match.times.estimatedStartTime < currentStart
        {
            return true
        }

        // Match start + buffer is in the past
        let matchDurationBufferMs: Int64 = 3 * 60 * 1000
        let estimatedEnd =
            match.times.estimatedStartTime + matchDurationBufferMs
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return nowMs > estimatedEnd
    }

    /// The "current" on-field start time — the latest start time among
    /// "On field" matches.
    static func currentOnFieldStart(in matches: [Match]) -> Int64? {
        matches
            .filter { $0.status.lowercased() == "on field" }
            .map { $0.times.estimatedStartTime }
            .max()
    }

    /// The match currently being played (if any).
    static func isCurrentlyPlaying(
        _ match: Match,
        currentOnFieldStart: Int64?
    ) -> Bool {
        match.status.lowercased() == "on field"
            && match.times.estimatedStartTime == currentOnFieldStart
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
            .max(by: {
                $0.times.estimatedStartTime < $1.times.estimatedStartTime
            })
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

    /// Canonical label, colour and icon for a status. Every iOS surface reads
    /// from here so they can't drift apart.
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
}
