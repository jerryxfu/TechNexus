import ComposeApp
import SwiftUI

struct MatchCardView: View {
    let match: Match
    let highlightedTeams: [String: Color]
    let currentOnFieldStart: Int64?
    @ObservedObject private var network = NetworkMonitor.shared

    // MARK: - Match state

    // MARK: - Teams (nil -> "N/A")

    private var redTeams: [String] {
        guard let teams = match.redTeams else {
            return ["N/A"]
        }
        var result: [String] = []
        for team in teams {
            result.append((team as? String) ?? "N/A")
        }
        return result
    }

    private var blueTeams: [String] {
        guard let teams = match.blueTeams else {
            return ["N/A"]
        }
        var result: [String] = []
        for team in teams {
            result.append((team as? String) ?? "N/A")
        }
        return result
    }

    // MARK: - Match state

    private var hasHighlightedTeam: Bool {
        redTeams.contains { highlightedTeams[$0] != nil }
            || blueTeams.contains { highlightedTeams[$0] != nil }
    }

    private var isDone: Bool {
        MatchStatusHelper.isDone(
            match,
            currentOnFieldStart: currentOnFieldStart
        )
    }

    private var isCurrentlyPlaying: Bool {
        MatchStatusHelper.isCurrentlyPlaying(
            match,
            currentOnFieldStart: currentOnFieldStart
        )
    }

    private var isActive: Bool {
        let s = match.status.lowercased()
        return isCurrentlyPlaying || s == "on deck" || s == "now queuing"
    }

    private var statusInfo: (text: String, color: Color, icon: String) {
        MatchStatusHelper.display(
            for: match.status,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
    }

    /// True if the match is more than 30 minutes away from its queuing time.
    /// If queue time is unknown, fall back to the start time.
    private var isFarFromQueuing: Bool {
        let queueTimeMs =
            match.times.queueTime?.int64Value
            ?? match.times.startTime
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let threshold: Int64 = 10 * 60 * 1000
        return (queueTimeMs - nowMs) > threshold
    }

    private var highlightBorderColor: Color {
        for team in redTeams + blueTeams {
            if let color = highlightedTeams[team] {
                return color
            }
        }
        return .yellow
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isDone {
                collapsedView
            } else {
                fullView
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDone
                        ? Color(.systemGray5)
                        : hasHighlightedTeam
                            ? highlightBorderColor.opacity(0.6)
                            : isActive
                                ? statusInfo.color.opacity(0.4)
                                : Color(.systemGray5),
                    lineWidth: isDone
                        ? 0.5
                        : hasHighlightedTeam ? 2 : isActive ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isDone
                ? .clear
                : hasHighlightedTeam
                    ? highlightBorderColor.opacity(0.15)
                    : isActive ? statusInfo.color.opacity(0.1) : .clear,
            radius: 8,
            y: 2
        )
    }

    // MARK: - Collapsed (done) view

    private var collapsedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    TimeFormatting.relativeTime(match.times.startTime)
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        // Index-keyed on purpose: team strings are not unique once teamList() maps missing entries to "N/A"
                        ForEach(Array(redTeams.enumerated()), id: \.offset) { _, team in
                            TeamPill(
                                team: team,
                                color: .red,
                                compact: true,
                                highlight: highlightedTeams[team]
                            )
                        }
                    }

                    Text("vs")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 3) {
                        // Index-keyed on purpose: team strings are not unique once teamList() maps missing entries to "N/A"
                        ForEach(Array(blueTeams.enumerated()), id: \.offset) { _, team in
                            TeamPill(
                                team: team,
                                color: .blue,
                                compact: true,
                                highlight: highlightedTeams[team]
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(0.65)
    }

    // MARK: - Full view

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.label)
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                if !isFarFromQueuing {
                    LiveStatusBadge(
                        text: statusInfo.text,
                        color: statusInfo.color,
                        icon: statusInfo.icon,
                        isLive: network.isConnected && !isDone
                    )
                }
            }

            HStack(spacing: 6) {
                // "RED"/"BLUE" in quals, "A3"/"A?" in playoffs.
                teamRow(
                    label: MatchStatusHelper.allianceLabel(
                        for: match,
                        isRed: true
                    ),
                    teams: redTeams,
                    color: .red
                )
                teamRow(
                    label: MatchStatusHelper.allianceLabel(
                        for: match,
                        isRed: false
                    ),
                    teams: blueTeams,
                    color: .blue
                )
            }

            TimingCarouselView(times: match.times)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
    }

    // MARK: - Team row

    private func teamRow(label: String, teams: [String], color: Color)
        -> some View
    {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color.opacity(0.7))
                // Index-keyed on purpose: team strings are not unique once teamList() maps missing entries to "N/A"
                ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                    TeamPill(
                        team: team,
                        color: color,
                        compact: false,
                        highlight: highlightedTeams[team]
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(color.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }
}
