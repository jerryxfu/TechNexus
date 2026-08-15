import ComposeApp
import SwiftUI

struct ScheduleHeaderView: View {
    let event: Event?
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var blinkOn = true

    var body: some View {
        VStack(spacing: 4) {
            if let event {
                Text(event.eventKey)
                    .font(.system(size: 24, weight: .bold))

                if let latest = latestMatch(in: event) {
                    HStack(spacing: 6) {
                        Text(latest.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(latest.status)
                                .fontWeight(.semibold)
                                .foregroundStyle(statusColor(latest.status))
                            if network.isConnected {
                                Circle()
                                    .fill(statusColor(latest.status))
                                    .frame(width: 6, height: 6)
                                    .opacity(blinkOn ? 1.0 : 0.25)
                                    .onAppear {
                                        withAnimation(
                                            .easeInOut(duration: 0.8)
                                                .repeatForever(
                                                    autoreverses: true
                                                )
                                        ) {
                                            blinkOn = false
                                        }
                                    }
                            }
                        }
                    }
                    .font(.system(size: 14))
                } else {
                    Text(
                        "\(event.matches.count) matches · updated \(TimeFormatting.formatDateTime(event.dataAsOfTime))"
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Schedule")
                    .font(.system(size: 24, weight: .bold))
                Text("Loading...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func latestMatch(in event: Event) -> Match? {
        let onFieldMatches = event.matches.filter {
            $0.status.lowercased() == "on field"
        }
        if let currentOnField = onFieldMatches.max(by: {
            $0.times.estimatedStartTime < $1.times.estimatedStartTime
        }) {
            return currentOnField
        }

        let priority = ["on deck", "now queuing", "queuing soon"]
        for status in priority {
            if let match = event.matches.first(where: {
                $0.status.lowercased() == status
            }) {
                return match
            }
        }

        return nil
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "on field": return .green
        case "on deck": return .blue
        case "now queuing": return .orange
        case "queuing soon": return .purple
        default: return .secondary
        }
    }
}
