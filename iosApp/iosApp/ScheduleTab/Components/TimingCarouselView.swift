import ComposeApp
import SwiftUI

struct TimingCarouselView: View {
    let times: MatchTimes

    @State private var selection: Int = 0
    @State private var hasInitialized = false

    private struct TimingEntry {
        let label: String
        let epoch: Int64
    }

    private var entries: [TimingEntry] {
        // Every Nexus timestamp is nullable, so every row is conditional.
        // On Field and Start used to be appended unconditionally because
        // the model declared them non-null; a playoff match with no
        // published schedule would have shown 1 Jan 1970.
        var result: [TimingEntry] = []
        if let queue = times.queueTime?.int64Value {
            result.append(TimingEntry(label: "Queue", epoch: queue))
        }
        if let onDeck = times.onDeckTime?.int64Value {
            result.append(TimingEntry(label: "On Deck", epoch: onDeck))
        }
        if let onField = times.onFieldTime?.int64Value {
            result.append(TimingEntry(label: "On Field", epoch: onField))
        }
        if let start = times.estimatedStartTime?.int64Value
            ?? times.actualStartTime?.int64Value
        {
            result.append(TimingEntry(label: "Start", epoch: start))
        }
        return result
    }

    /// Index of the next upcoming timing (or last one if all have passed)
    private var nextUpcomingIndex: Int {
        guard !entries.isEmpty else { return 0 }
        let now = Date().timeIntervalSince1970 * 1000
        if let idx = entries.firstIndex(where: { Double($0.epoch) > now }) {
            return idx
        }
        return entries.count - 1
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(selection > 0 ? .secondary : .tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(
                        selection < entries.count - 1 ? .secondary : .tertiary
                    )
            }
            .frame(width: 12)

            TabView(selection: $selection) {
                ForEach(Array(entries.enumerated()), id: \.offset) {
                    index,
                    entry in
                    HStack(spacing: 4) {
                        Text("\(entry.label):")
                            .font(.system(size: 14))

                        Text(TimeFormatting.relativeTime(entry.epoch))
                            .font(.system(size: 14))

                        Text("(" + TimeFormatting.formatTime(entry.epoch) + ")")
                            .font(.system(size: 14))

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 22)

            // Spacing, not just the TabView, sets the carousel's height. Four
            // entries at 4pt with 3pt between them is 25pt, so the dot column
            // was the taller of the two and shrinking the TabView alone did
            // nothing. 4x4 + 3x2 = 22, which now matches it.
            VStack(spacing: 2) {
                ForEach(0..<entries.count, id: \.self) { i in
                    Circle()
                        .fill(
                            selection == i
                                ? Color.primary.opacity(0.6)
                                : Color.secondary.opacity(0.25)
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .onAppear {
            if !hasInitialized {
                selection = nextUpcomingIndex
                hasInitialized = true
            }
        }
    }
}
