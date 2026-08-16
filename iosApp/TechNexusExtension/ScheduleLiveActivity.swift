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
                context.state.matchStatus
            )

            return DynamicIsland {
                // MARK: - Expanded view
                // Fixed sizes below are deliberate: Dynamic Island regions have
                // hard pixel budgets and barely honour Dynamic Type. See STYLE.md.
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.matchLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                        HStack(spacing: 3) {
                            if context.isStale {
                                Image(systemName: LiveActivityFormat.staleIcon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Text(context.state.matchStatus)
                                .font(.caption2)
                                .foregroundStyle(statusColor)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: timer.range,
                            countsDown: timer.countsDown
                        )
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(timer.isOverdue ? .orange : .primary)
                        .frame(maxWidth: 80, alignment: .trailing)

                        Text(
                            timer.isOverdue
                                ? "since \(LiveActivityFormat.time(epoch: context.state.startTimeEpoch))"
                                : LiveActivityFormat.time(
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
                        HStack(spacing: 6) {
                            teamsLine(context.state.redTeams, color: .red)
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            teamsLine(context.state.blueTeams, color: .blue)
                        }

                        if !context.state.highlightedTeamsSummary.isEmpty {
                            highlightedTeamsRow(
                                context.state.highlightedTeamsSummary
                            )
                        }
                    }
                    .padding(.top, 2)
                    .opacity(
                        context.isStale ? LiveActivityFormat.staleOpacity : 1
                    )
                }
                // MARK: - Compact view
            } compactLeading: {
                Text(LiveActivityFormat.compactLabel(context.state.matchLabel))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            } compactTrailing: {
                Group {
                    if LiveActivityFormat.fitsCompactCountdown(
                        epoch: context.state.startTimeEpoch
                    ) {
                        Text(
                            timerInterval: timer.range,
                            countsDown: timer.countsDown
                        )
                        .foregroundStyle(timer.isOverdue ? .orange : .primary)
                    } else {
                        // Beyond an hour out a live countdown reads H:MM:SS and
                        // truncates in ~60pt. Clock time is shorter and more useful.
                        Text(
                            LiveActivityFormat.time(
                                epoch: context.state.startTimeEpoch
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(maxWidth: 60, alignment: .trailing)
            } minimal: {
                // Symbol varies by status, not just its tint — this region has
                // room for one glyph and colour alone isn't accessible.
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
                let presentation = LiveActivityFormat
                    .highlightedPresentation(info)
                let tint =
                    LiveActivityFormat.color(hex: info.colorHex) ?? .yellow

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
        .opacity(isStale ? LiveActivityFormat.staleOpacity : 1)
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
                            LiveActivityFormat.statusColor(state.matchStatus)
                        )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(timerInterval: timer.range, countsDown: timer.countsDown)
                    .font(.system(.headline, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(timer.isOverdue ? .orange : .primary)

                Text(
                    timer.isOverdue
                        ? "overdue since \(LiveActivityFormat.time(epoch: state.startTimeEpoch))"
                        : LiveActivityFormat.time(epoch: state.startTimeEpoch)
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
                let presentation = LiveActivityFormat
                    .highlightedPresentation(info)

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
