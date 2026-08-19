import SwiftUI

/// Shared by the Dynamic Island and the Lock Screen presentations.
///
/// Note this deliberately does *not* share `MatchStatusHelper` from the app
/// target. That file imports ComposeApp for the `Match` type, which the
/// extension doesn't link and it maps *raw* API statuses, whereas everything
/// here maps the already-resolved display strings the manager sends over.
enum LiveActivityFormat {

    // MARK: - Colour

    static func color(hex: String) -> Color? {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16)
        else {
            return nil
        }

        let red = Double((value & 0xFF00_00) >> 16) / 255.0
        let green = Double((value & 0x00_FF_00) >> 8) / 255.0
        let blue = Double(value & 0x00_00_FF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    /// Stale data reads gray everywhere. A green "On field" that might be
    /// twenty minutes old is worse than no colour at all.
    static func statusColor(_ status: String, isStale: Bool = false) -> Color {
        guard !isStale else { return .gray }
        switch status.lowercased() {
        case "on field": return .green
        case "on deck": return .blue
        case "now queuing": return .orange
        case "queuing soon": return .purple
        default: return .gray
        }
    }

    /// SF Symbol for a status. The minimal presentation has room for one glyph
    /// and nothing else, so it can't rely on colour alone.
    static func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "on field": return "flag.fill"
        case "on deck": return "clock.fill"
        case "now queuing": return "figure.walk"
        case "queuing soon": return "hourglass"
        default: return "circle"
        }
    }

    // MARK: - Appearance

    /// Translucent on purpose: the wallpaper reads through instead of the card
    /// presenting a hard black slab. Tune it here, it is set nowhere else.
    static let backgroundTint = Color.black.opacity(0.55)
    static let systemActionForeground = Color.white

    /// Shown next to anything that may no longer be current.
    static let staleIcon = "icloud.slash"

    // MARK: - Time

    // Cached, the Live Activity re-renders on every update.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(epoch: Int64) -> String {
        timeFormatter.string(
            from: Date(timeIntervalSince1970: Double(epoch) / 1000.0)
        )
    }

    struct MatchTimer {
        let range: ClosedRange<Date>
        let countsDown: Bool
        /// True once the scheduled start has passed, so the timer is counting
        /// up and the number on screen is how overdue the match is.
        var isOverdue: Bool { !countsDown }
    }

    /// Counts down to the scheduled start, then counts up once it passes.
    /// A late match reads as "how long overdue" instead of freezing at 0:00,
    /// which is the difference between "no information" and "the field is
    /// running behind".
    static func matchTimer(epoch: Int64) -> MatchTimer {
        let now = Date.now
        let start = Date(timeIntervalSince1970: Double(epoch) / 1000.0)

        if start > now {
            return MatchTimer(range: now...start, countsDown: true)
        }
        // Headroom for the count-up; the label stops at the upper bound.
        return MatchTimer(
            range: start...now.addingTimeInterval(60 * 60),
            countsDown: false
        )
    }

    /// Clarifies the match's time relative to now.
    static func timeLabel(epoch: Int64, status: String) -> String {
        let clock = time(epoch: epoch)
        guard matchTimer(epoch: epoch).isOverdue else {
            return "starts \(clock)"
        }
        return status.lowercased() == "on field"
            ? "started \(clock)"
            : "due \(clock)"
    }

    static func relative(epoch: Int64) -> String {
        let seconds = Int(
            Date(timeIntervalSince1970: Double(epoch) / 1000.0)
                .timeIntervalSinceNow
        )
        if abs(seconds) < 60 { return "now" }

        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let prefix = seconds > 0 ? "in " : ""
        let suffix = seconds > 0 ? "" : " ago"

        if hours > 0 {
            let body = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
            return "\(prefix)\(body)\(suffix)"
        }
        return "\(prefix)\(minutes)m\(suffix)"
    }

    // MARK: - Labels

    /// Splits a Nexus label into the match type and everything identifying the
    /// match within it: `"Qualification 15"` -> `("Qualification", "15")`.
    ///
    /// The label set is documented: `Practice N`, `Qualification N`, `Qualification N Replay`, `Playoff N`, `Final N`
    ///
    /// Parsed in the extension rather than sent over in `ContentState`, unlike
    /// the alliance labels. Those need `Match.isPlayoff` and the extension
    /// can't link ComposeApp; this needs nothing but the string.
    static func matchLabelParts(_ label: String) -> (
        type: String, number: String
    ) {
        let parts = label.split(separator: " ")
        guard parts.count >= 2 else { return (label, "") }
        return (String(parts[0]), parts.dropFirst().joined(separator: " "))
    }

    /// "Qualification 15" -> "Q15", "Practice 4" -> "P4", "Qualification 24 Replay" -> "Q24R"
    static func compactLabel(_ label: String) -> String {
        let (type, number) = matchLabelParts(label)
        let tokens = number.split(separator: " ")
        guard let initial = type.first, let digits = tokens.first else {
            return String(label.prefix(3))
        }
        let suffix = tokens.dropFirst()
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
        return "\(initial)\(digits)\(suffix)"
    }

    static func statusWithEta(_ info: HighlightedTeamInfo) -> String {
        guard let epoch = info.statusEtaEpoch else { return info.status }
        let relativeText = relative(epoch: epoch)
        return relativeText == "now"
            ? "\(info.status) now" : "\(info.status) \(relativeText)"
    }

    /// A team queuing more than ten minutes out is de-emphasised, since it isn't actionable yet.
    static func highlightedPresentation(
        _ info: HighlightedTeamInfo,
        isStale: Bool = false
    ) -> (text: String, color: Color) {
        guard
            info.status.lowercased() == "queuing soon",
            let epoch = info.statusEtaEpoch
        else {
            return (
                statusWithEta(info), statusColor(info.status, isStale: isStale)
            )
        }

        let seconds = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
            .timeIntervalSinceNow
        if seconds > 10 * 60 {
            return ("Queuing \(relative(epoch: epoch))", .gray)
        }

        return (statusWithEta(info), statusColor(info.status))
    }
}
