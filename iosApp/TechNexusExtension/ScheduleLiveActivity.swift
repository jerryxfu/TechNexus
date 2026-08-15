import ActivityKit
import SwiftUI
import WidgetKit

private func colorFromHex(_ hex: String) -> Color? {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.hasPrefix("#") {
        sanitized.removeFirst()
    }

    guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16)
    else {
        return nil
    }

    let red = Double((value & 0xFF0000) >> 16) / 255.0
    let green = Double((value & 0x00FF00) >> 8) / 255.0
    let blue = Double(value & 0x0000FF) / 255.0
    return Color(red: red, green: green, blue: blue)
}

struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            ScheduleLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.matchLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(context.state.matchStatus)
                            .font(.caption2)
                            .foregroundStyle(
                                statusColor(context.state.matchStatus)
                            )
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: countdownRange(
                                epoch: context.state.startTimeEpoch
                            ),
                            countsDown: true
                        )
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(maxWidth: 80, alignment: .trailing)

                        Text(
                            formatTime(epoch: context.state.startTimeEpoch)
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Teams line
                        HStack(spacing: 6) {
                            teamsLine(
                                context.state.redTeams,
                                color: .red
                            )
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            teamsLine(
                                context.state.blueTeams,
                                color: .blue
                            )
                        }

                        // Highlighted teams
                        if !context.state.highlightedTeamsSummary.isEmpty {
                            highlightedTeamsRow(
                                context.state.highlightedTeamsSummary
                            )
                        }
                    }
                    .padding(.top, 2)
                }
                // MARK: - Compact view
            } compactLeading: {
                Text(compactLabel(context.state.matchLabel))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(context.state.matchStatus))
            } compactTrailing: {
                Text(
                    timerInterval: countdownRange(
                        epoch: context.state.startTimeEpoch
                    ),
                    countsDown: true
                )
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(maxWidth: 60, alignment: .trailing)
            } minimal: {
                Image(systemName: "flag.fill")
                    .foregroundStyle(statusColor(context.state.matchStatus))
            }
        }
    }

    // MARK: - Helpers

    private func teamsLine(_ teams: [String], color: Color) -> some View {
        HStack(spacing: 3) {
            // Index-keyed on purpose: team strings are not unique once
            // teamList() maps missing entries to "N/A", and duplicate IDs
            // can blank the whole activity.
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                Text(team)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
        }
    }

    private func highlightedTeamsRow(_ teams: [HighlightedTeamInfo])
        -> some View
    {
        HStack(spacing: 3) {
            ForEach(teams, id: \.team) { info in
                let presentation = highlightedStatusPresentation(info)
                HStack(spacing: 2) {
                    Circle()
                        .fill(colorFromHex(info.colorHex) ?? .yellow)
                        .frame(width: 4, height: 4)
                    Text("\(info.team) · \(presentation.text)")
                        .font(.system(size: 9))
                        .foregroundStyle(presentation.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    (colorFromHex(info.colorHex) ?? .yellow).opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func countdownRange(epoch: Int64) -> ClosedRange<Date> {
        let now = Date.now
        let start = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
        // Clamp to now so past scheduled times render as 0:00 instead of counting up.
        let end = max(start, now)
        return now...end
    }

    private func statusWithEta(_ info: HighlightedTeamInfo) -> String {
        guard let epoch = info.statusEtaEpoch else { return info.status }
        let relative = relativeTime(epoch: epoch)
        return relative == "now"
            ? "\(info.status) now" : "\(info.status) \(relative)"
    }

    private func highlightedStatusPresentation(_ info: HighlightedTeamInfo)
        -> (text: String, color: Color)
    {
        guard
            info.status.lowercased() == "queuing soon",
            let epoch = info.statusEtaEpoch
        else {
            return (statusWithEta(info), statusColor(info.status))
        }

        let seconds = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
            .timeIntervalSinceNow
        if seconds > 10 * 60 {
            let relative = relativeTime(epoch: epoch)
            return ("queuing \(relative)", .gray)
        }

        return (statusWithEta(info), statusColor(info.status))
    }

    private func relativeTime(epoch: Int64) -> String {
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

    private func formatTime(epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "on field": return .green
        case "on deck": return .blue
        case "now queuing": return .orange
        case "queuing soon": return .purple
        default: return .gray
        }
    }

    private func compactLabel(_ label: String) -> String {
        // Trim long labels like "Qualification 15" -> "Q15"
        let parts = label.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first {
            return "\(first)\(parts.last ?? "")"
        }
        return String(label.prefix(3))
    }
}

// MARK: - Lock screen view

private struct ScheduleLockScreenView: View {
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: match label + status + time
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.matchLabel)
                        .font(.headline)
                    Text(state.matchStatus)
                        .font(.caption)
                        .foregroundStyle(statusColor(state.matchStatus))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(
                        timerInterval: countdownRange(
                            epoch: state.startTimeEpoch
                        ),
                        countsDown: true
                    )
                    .font(.system(.headline, design: .monospaced))
                    .monospacedDigit()

                    Text(formatTime(epoch: state.startTimeEpoch))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Teams
            HStack(spacing: 6) {
                teamsBox(state.redTeams, color: .red, label: "RED")
                teamsBox(state.blueTeams, color: .blue, label: "BLUE")
            }

            // Highlighted teams
            if !state.highlightedTeamsSummary.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR TEAMS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    ForEach(state.highlightedTeamsSummary, id: \.team) { info in
                        let presentation = highlightedStatusPresentation(info)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorFromHex(info.colorHex) ?? .yellow)
                                .frame(width: 5, height: 5)
                            Text(info.team)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("· \(info.matchLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text(presentation.text)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(presentation.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func teamsBox(_ teams: [String], color: Color, label: String)
        -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                    Text(team)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatTime(epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func countdownRange(epoch: Int64) -> ClosedRange<Date> {
        let now = Date.now
        let start = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
        let end = max(start, now)
        return now...end
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "on field": return .green
        case "on deck": return .blue
        case "now queuing": return .orange
        case "queuing soon": return .purple
        default: return .gray
        }
    }

    private func statusWithEta(_ info: HighlightedTeamInfo) -> String {
        guard let epoch = info.statusEtaEpoch else { return info.status }
        let relative = relativeTime(epoch: epoch)
        return relative == "now"
            ? "\(info.status) now" : "\(info.status) \(relative)"
    }

    private func highlightedStatusPresentation(_ info: HighlightedTeamInfo)
        -> (text: String, color: Color)
    {
        guard
            info.status.lowercased() == "queuing soon",
            let epoch = info.statusEtaEpoch
        else {
            return (statusWithEta(info), statusColor(info.status))
        }

        let seconds = Date(timeIntervalSince1970: Double(epoch) / 1000.0)
            .timeIntervalSinceNow
        if seconds > 10 * 60 {
            let relative = relativeTime(epoch: epoch)
            return ("Queuing \(relative)", .gray)
        }

        return (statusWithEta(info), statusColor(info.status))
    }

    private func relativeTime(epoch: Int64) -> String {
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
}
