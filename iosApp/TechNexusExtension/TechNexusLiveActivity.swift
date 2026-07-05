import ActivityKit
import SwiftUI
import WidgetKit

struct TechNexusAttributes: ActivityAttributes {// WARNING : slop because i had an error. live activity probably isnt working. check commit from jul 4 2026 at 20:25
    public struct ContentState: Codable, Hashable {
        // Live activity dynamic state
        var phaseName: String
        var activeAllianceName: String?
        var totalSecondsRemaining: Int
        var phaseSecondsRemaining: Int
    }
    // Static, non-changing attributes (none for now)
}

struct TechNexusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TechNexusAttributes.self) { context in
            // Lock screen / Live Activity view
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phaseName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    if let alliance = context.state.activeAllianceName {
                        Text(alliance)
                            .font(.caption2)
                            .foregroundStyle(
                                alliance == "Red" ? Color.red : Color.blue
                            )
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        timerInterval: timerRange(
                            remaining: context.state.totalSecondsRemaining
                        ),
                        countsDown: true
                    )
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .monospacedDigit()

                    Text("\(context.state.phaseSecondsRemaining)s left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phaseName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        if let alliance = context.state.activeAllianceName {
                            Text(alliance)
                                .font(.caption2)
                                .foregroundStyle(
                                    alliance == "Red" ? Color.red : Color.blue
                                )
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: timerRange(
                                remaining: context.state.totalSecondsRemaining
                            ),
                            countsDown: true
                        )
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()

                        Text("\(context.state.phaseSecondsRemaining)s left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
            } compactLeading: {
                Text(compactPhaseName(context.state.phaseName))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(phaseColor(name: context.state.phaseName))
            } compactTrailing: {
                Text(
                    timerInterval: timerRange(
                        remaining: context.state.totalSecondsRemaining
                    ),
                    countsDown: true
                )
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
            } minimal: {
                Text(formatTime(context.state.totalSecondsRemaining))
                    .font(.system(.caption2, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Helpers

    private func timerRange(remaining: Int) -> ClosedRange<Date> {
        let now = Date.now
        let end = now.addingTimeInterval(Double(max(remaining, 0)))
        return now...end
    }

    private func phaseColor(name: String) -> Color {
        switch name {
        case "Autonomous": return .green
        case "Auto end pause", "Transition": return .gray
        case "Endgame": return .orange
        case _ where name.hasPrefix("Alliance shift"): return .blue
        default: return .gray
        }
    }

    private func compactPhaseName(_ name: String) -> String {
        switch name {
        case "Autonomous": return "AUTO"
        case "Auto end pause": return "PAUSE"
        case "Transition": return "TRANS"
        case "Endgame": return "END"
        case _ where name.hasPrefix("Alliance shift"):
            let num = name.last.map(String.init) ?? ""
            return "S\(num)"
        default: return "—"
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
