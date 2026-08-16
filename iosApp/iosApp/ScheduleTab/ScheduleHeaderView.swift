import ComposeApp
import SwiftUI

struct ScheduleHeaderView: View {
    let event: Event?
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var isDimmed = false

    var body: some View {
        VStack(spacing: 4) {
            if let event {
                Text(event.eventKey)
                    .font(.system(size: 24, weight: .bold))

                if let latest = MatchStatusHelper.latestMatch(in: event) {
                    let info = MatchStatusHelper.display(for: latest, in: event)

                    HStack(spacing: 6) {
                        Text(latest.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(info.text)
                                .fontWeight(.semibold)
                                .foregroundStyle(info.color)
                            if network.isConnected {
                                blinkDot(color: info.color)
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

    /// Driven by a value that flips on both appear and disappear, so the
    /// animation restarts after a tab switch instead of freezing on one frame.
    private func blinkDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isDimmed ? 0.25 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isDimmed
            )
            .onAppear { isDimmed = true }
            .onDisappear { isDimmed = false }
    }
}
