import ActivityKit
import SwiftUI
import WidgetKit

struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            ScheduleLockScreenView(
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(LiveActivityFormat.backgroundTint)
            .activitySystemActionForegroundColor(
                LiveActivityFormat.systemActionForeground
            )
        } dynamicIsland: { context in
            let timer = LiveActivityFormat.matchTimer(
                epoch: context.state.startTimeEpoch
            )
            let statusColor = LiveActivityFormat.statusColor(
                context.state.matchStatus,
                isStale: context.isStale
            )

            return DynamicIsland {
                // Left and right of the dynamic island is the field status and time.
                // Below that is the main label and match timer. Then under that are the teams.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        if context.isStale {
                            Image(systemName: LiveActivityFormat.staleIcon)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(context.state.matchStatus)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    // Clears the 44pt corner curve, which was clipping glyphs.
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(
                        LiveActivityFormat.timeLabel(
                            epoch: context.state.startTimeEpoch,
                            status: context.state.matchStatus
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(context.state.matchLabel)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 3) {
                                allianceRow(
                                    context.state.redTeams,
                                    color: .red
                                )
                                allianceRow(
                                    context.state.blueTeams,
                                    color: .blue
                                )
                            }
                            .fixedSize()

                            Text(
                                timerInterval: timer.range,
                                countsDown: timer.countsDown
                            )
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            // The timer reserves width for its longest value.
                            // Trailing alignment makes it grow leftward instead of parking the digits with a gap on the right.
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(
                                context.isStale
                                    ? .gray
                                    : (timer.isOverdue ? .orange : .primary)
                            )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if !context.state.highlightedTeamsSummary.isEmpty {
                            highlightedTeamsRow(
                                context.state.highlightedTeamsSummary,
                                isStale: context.isStale
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                // MARK: - Compact view
            } compactLeading: {  // left side
                Text(LiveActivityFormat.compactLabel(context.state.matchLabel))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            } compactTrailing: {  // right side
                Text(
                    timerInterval: timer.range,
                    countsDown: timer.countsDown
                ).foregroundStyle(
                    context.isStale
                        ? .gray : (timer.isOverdue ? .orange : .primary)
                )
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                // Same reason as the expanded timer: Text(timerInterval:) reserves width for its longest value,
                // so without this the digits sit centred and leave a gap on the right.
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60, alignment: .trailing)
            } minimal: {
                // Symbol varies by status, not just its tint. This region has room for one glyph and colour alone isn't accessible.
                Image(
                    systemName: context.isStale
                        ? LiveActivityFormat.staleIcon
                        : LiveActivityFormat.statusIcon(
                            context.state.matchStatus
                        )
                )
                .foregroundStyle(context.isStale ? .secondary : statusColor)
            }
        }
    }

    // MARK: - Subviews

    /// One alliance per row, no RED/BLUE labels. Fixed-width cells keep the two rows aligned with each other.
    private func allianceRow(_ teams: [String], color: Color) -> some View {
        HStack(spacing: 4) {
            // Index-keyed on purpose: team strings are not unique once teamList() maps missing entries to "N/A"
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                Text(team)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 38)
            }
        }
    }

    private func highlightedTeamsRow(
        _ teams: [HighlightedTeamInfo],
        isStale: Bool
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(teams, id: \.team) { info in
                let presentation =
                    LiveActivityFormat
                    .highlightedPresentation(info, isStale: isStale)
                let tint =
                    LiveActivityFormat.color(hex: info.colorHex) ?? .yellow

                HStack(spacing: 2) {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                    Text("\(info.team) · \(presentation.text)")
                        .font(.caption2)
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
    let isStale: Bool

    private var timer: LiveActivityFormat.MatchTimer {
        LiveActivityFormat.matchTimer(epoch: state.startTimeEpoch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(spacing: 6) {
                teamsBox(state.redTeams, color: .red, label: "RED")
                teamsBox(state.blueTeams, color: .blue, label: "BLUE")
            }

            if !state.highlightedTeamsSummary.isEmpty {
                Divider()
                highlightedTeams
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.matchLabel)
                    .font(.headline)
                HStack(spacing: 4) {
                    if isStale {
                        Image(systemName: LiveActivityFormat.staleIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(state.matchStatus)
                        .font(.caption)
                        .foregroundStyle(
                            LiveActivityFormat.statusColor(
                                state.matchStatus,
                                isStale: isStale
                            )
                        )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(timerInterval: timer.range, countsDown: timer.countsDown)
                    .font(.system(.headline, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(
                        isStale ? .gray : (timer.isOverdue ? .orange : .primary)
                    )

                Text(
                    LiveActivityFormat.timeLabel(
                        epoch: state.startTimeEpoch,
                        status: state.matchStatus
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }

    private var highlightedTeams: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("YOUR TEAMS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)

            ForEach(state.highlightedTeamsSummary, id: \.team) { info in
                let presentation =
                    LiveActivityFormat
                    .highlightedPresentation(info, isStale: isStale)

                HStack(spacing: 5) {
                    Circle()
                        .fill(
                            LiveActivityFormat.color(hex: info.colorHex)
                                ?? .yellow
                        )
                        .frame(width: 5, height: 5)
                    Text(info.team)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("· \(info.matchLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Text(presentation.text)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(presentation.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    private func teamsBox(_ teams: [String], color: Color, label: String)
        -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                    Text(team)
                        .font(.caption)
                        .fontWeight(.medium)
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
