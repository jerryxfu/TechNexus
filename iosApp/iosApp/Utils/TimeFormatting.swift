import Foundation

enum TimeFormatting {
    // Cached: DateFormatter is expensive to build, and these are called once
    // per match on every 15s refresh. Only used from the main actor.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    /// Format an epoch (in milliseconds) as a short time string like "3:45 PM"
    static func formatTime(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        return timeFormatter.string(from: date)
    }

    /// Format an epoch (in milliseconds) as a short date+time string
    static func formatDateTime(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        return dateTimeFormatter.string(from: date)
    }

    /// Relative time description like "in 5m", "in 1h 20m", "3m ago", "now"
    static func relativeTime(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let diff = date.timeIntervalSinceNow

        if abs(diff) < 60 {
            return "now"
        }

        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)

        if diff > 0 {
            if hours > 0 {
                let remainingMin = minutes - hours * 60
                return remainingMin > 0
                    ? "in \(hours)h \(remainingMin)m"
                    : "in \(hours)h"
            }
            return "in \(minutes)m"
        } else {
            if hours < 0 {
                let remainingMin = abs(minutes) - abs(hours) * 60
                return remainingMin > 0
                    ? "\(abs(hours))h \(remainingMin)m ago"
                    : "\(abs(hours))h ago"
            }
            return "\(abs(minutes))m ago"
        }
    }
}
