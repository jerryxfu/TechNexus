import ActivityKit
import SwiftUI
import WidgetKit

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
                                LiveActivityFormat.statusColor(
                                    context.state.matchStatus
                                )
                            )
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: LiveActivityFormat.countdownRange(
                                epoch: context.state.startTimeEpoch
                            ),
                            countsDown: true
                        )
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(maxWidth: 80, alignment: .trailing)

                        Text(
                            LiveActivityFormat.time(
                                epoch: context.state.startTimeEpoch
                            )
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
                            teamsLine(context.state.redTeams, color: .red)
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            teamsLine(context.state.blueTeams, color: .blue)
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
                Text(LiveActivityFormat.compactLabel(context.state.matchLabel))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LiveActivityFormat.statusColor(
                            context.state.matchStatus
                        )
                    )
            } compactTrailing: {
                Text(
                    timerInterval: LiveActivityFormat.countdownRange(
                        epoch: context.state.startTimeEpoch
                    ),
                    countsDown: true
                )
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(maxWidth: 60, alignment: .trailing)
            } minimal: {
                Image(
                    systemName: LiveActivityFormat.statusIcon(
                        context.state.matchStatus
                    )
                )
                .foregroundStyle(
                    LiveActivityFormat.statusColor(context.state.matchStatus)
                )
            }
        }
    }

    // MARK: - Subviews

    private func teamsLine(_ teams: [String], color: Color) -> some View {
        HStack(spacing: 3) {
            // Index-keyed on purpose: team strings are not unique once teamList() maps missing entries to "N/A",
            // and duplicate IDs can blank the whole activity.
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
                let presentation = LiveActivityFormat
                    .highlightedPresentation(info)
                let tint = LiveActivityFormat.color(hex: info.colorHex) ?? .yellow

                HStack(spacing: 2) {
                    Circle()
                        .fill(tint)
                        .frame(width: 4, height: 4)
                    Text("\(info.team) · \(presentation.text)")
                        .font(.system(size: 9))
                        .foregroundStyle(presentation.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
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
                        .foregroundStyle(
                            LiveActivityFormat.statusColor(state.matchStatus)
                        )
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(
                        timerInterval: LiveActivityFormat.countdownRange(
                            epoch: state.startTimeEpoch
                        ),
                        countsDown: true
                    )
                    .font(.system(.headline, design: .monospaced))
                    .monospacedDigit()

                    Text(LiveActivityFormat.time(epoch: state.startTimeEpoch))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                        let presentation = LiveActivityFormat
                            .highlightedPresentation(info)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(
                                    LiveActivityFormat.color(
                                        hex: info.colorHex
                                    ) ?? .yellow
                                )
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
}
