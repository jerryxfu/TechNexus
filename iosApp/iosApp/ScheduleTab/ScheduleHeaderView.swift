import ComposeApp
import SwiftUI

struct ScheduleHeaderView: View {
    let event: Event?

    /// When this phone last got a response. Nil until the first success, which
    /// is the only time the chip is hidden, after that it only ever grows.
    let lastFetch: Date?

    @ObservedObject private var network = NetworkMonitor.shared
    @State private var isDimmed = false

    /// Past this, the data is old enough to say so. Six missed polls: long
    /// enough that a single dropped request doesn't cry wolf, short enough to
    /// notice before you walk to the wrong field.
    private static let staleAfter: TimeInterval = 90

    /// Reserved width for the chip, mirrored on the leading side so the event
    /// key stays optically centred. Fixed rather than intrinsic because the chip
    /// changes width as it counts ("8s" to "12m"), and a centred title that
    /// shifts sideways every fifteen seconds is worse than a little dead space.
    private static let chipWidth: CGFloat = 56

    var body: some View {
        VStack(spacing: 2) {
            if let event {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: Self.chipWidth, height: 0)

                    Text(event.eventKey)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)

                    freshnessChip
                        .frame(width: Self.chipWidth, alignment: .trailing)
                }

                // skippingFinished so the header moves on to the next
                // queuing match instead of sitting on grey "Done" forever.
                if let latest = MatchStatusHelper.latestMatch(
                    in: event,
                    skippingFinished: true
                ) {
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
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                } else {
                    Text("\(event.matches.count) matches")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Schedule")
                    .font(.title3)
                    .bold()
                Text("Loading...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: - Freshness

    /// How long ago the last response arrived.
    ///
    /// `TimelineView` rather than a `Timer` or a poll-driven state change: the
    /// text has to keep counting up when nothing else is happening, and "nothing
    /// else is happening" is precisely the offline case this exists to show. A
    /// state-driven version would freeze at whatever it said when the last
    /// refresh failed, which is the opposite of the intent.
    ///
    /// Scheduled from `lastFetch` so ticks land on the second the label changes.
    @ViewBuilder
    private var freshnessChip: some View {
        if let lastFetch {
            TimelineView(.periodic(from: lastFetch, by: 15)) { context in
                let age = max(0, context.date.timeIntervalSince(lastFetch))
                let isStale = age > Self.staleAfter

                HStack(spacing: 2) {
                    Image(
                        systemName: isStale
                            ? "icloud.slash" : "arrow.clockwise"
                    )
                    Text(Self.ageText(age))
                }
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(isStale ? Color.orange : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Last updated \(Self.ageText(age)) ago")
            }
        }
    }

    /// Deliberately terse, the chip has 56pt ish. "now", "45s", "12m", "3h".
    private static func ageText(_ age: TimeInterval) -> String {
        if age < 10 { return "now" }
        if age < 60 { return "\(Int(age))s" }
        if age < 3600 { return "\(Int(age / 60))m" }
        return "\(Int(age / 3600))h"
    }

    /// Driven by a value that flips on both appear and disappear,
    /// so the animation restarts after a tab switch instead of freezing on one frame.
    private func blinkDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .opacity(isDimmed ? 0.25 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isDimmed
            )
            // Frame on the outside so the slot stays a fixed 6x6 whatever the animation does inside and can't nudge the centred header.
            .frame(width: 6, height: 6)
            .task {
                // Started from onAppear, a repeatForever animation captures the insertion's geometry change too
                // and oscillates it forever which made the dot move left and right infinitely. Let layout settle.
                try? await Task.sleep(for: .milliseconds(50))
                isDimmed = true
            }
            .onDisappear { isDimmed = false }
    }
}
