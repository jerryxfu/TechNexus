import ComposeApp
import SwiftUI

/// Picks an event from the list Nexus publishes, so nobody has to know that
/// event keys exist.
///
/// Nexus purges past seasons, so this list is always short and always in the
/// future. Off-season it can legitimately be empty, which is why the demo entry
/// sits at the top rather than being tucked away as a fallback — for most of the
/// year it's the only thing that works.
struct EventPickerView: View {
    let currentEventId: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var network = NetworkMonitor.shared

    @State private var events: [EventSummary] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var search = ""
    @State private var demoNumber = ""

    var body: some View {
        NavigationStack {
            List {
                demoSection

                if isLoading {
                    loadingRow
                } else if loadFailed {
                    failureRow
                } else if events.isEmpty {
                    emptyRow
                } else if filtered.isEmpty {
                    noMatchesRow
                } else {
                    ForEach(groups, id: \.date) { group in
                        Section(header: Text(Self.sectionTitle(for: group.date))) {
                            ForEach(group.events, id: \.key) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search events")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Choose Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var demoSection: some View {
        Section {
            HStack(spacing: 2) {
                Text("demo")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("1815", text: $demoNumber)
                    .font(.system(.body, design: .monospaced))
                    .keyboardType(.numberPad)

                Spacer(minLength: 8)

                Button("Use") { select("demo" + demoNumber) }
                    .font(.subheadline.weight(.semibold))
                    .disabled(demoNumber.isEmpty)
            }
        } header: {
            Text("Demo event")
        } footer: {
            Text(
                "Demo events are created on frc.nexus and are always named demo followed by a number."
            )
        }
    }

    private func eventRow(_ event: EventSummary) -> some View {
        Button {
            select(event.key)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(event.key)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let span = Self.spanLabel(for: event) {
                            Text(span)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 0)

                if event.key == currentEventId {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading events…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The device knows whether it's online, so the copy shouldn't guess. Blaming
    /// the user's connection when the server is down produces bug reports that
    /// send teams hunting through venue wifi settings for an hour.
    private var failureRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load events.")
                .font(.subheadline)
            Text(
                network.isConnected
                    ? "The server isn't responding. This is on our end — try again in a moment."
                    : "You're offline. Reconnect, then try again."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await load() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No events scheduled.")
                .font(.subheadline)
            Text(
                "Nexus only lists current and upcoming events. Enter a demo event above to try the app in the meantime."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var noMatchesRow: some View {
        Text("No events match \"\(search)\".")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    // MARK: - Data

    private var filtered: [EventSummary] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return events }
        return events.filter {
            $0.name.lowercased().contains(query)
                || $0.key.lowercased().contains(query)
        }
    }

    private struct DateGroup {
        let date: Date
        let events: [EventSummary]
    }

    /// Grouped by the day an event starts. `Dictionary(grouping:)` loses order,
    /// so both the groups and the events inside them are re-sorted.
    private var groups: [DateGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: filtered) { event in
            calendar.startOfDay(for: Self.date(from: event.start))
        }
        return buckets.keys.sorted().map { day in
            DateGroup(
                date: day,
                events: (buckets[day] ?? []).sorted { $0.name < $1.name }
            )
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false

        do {
            events = try await BackendKt.getEvents()
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func select(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSelect(trimmed)
        dismiss()
    }

    // MARK: - Formatting

    private static func date(from epochMillis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(epochMillis) / 1000.0)
    }

    private static let sectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static func sectionTitle(for day: Date) -> String {
        sectionFormatter.string(from: day)
    }

    /// "through 31 Aug" for a multi-day event, nothing for a single day — the
    /// section header already carries the start.
    private static func spanLabel(for event: EventSummary) -> String? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date(from: event.start))
        let end = calendar.startOfDay(for: date(from: event.end))
        guard end > start else { return nil }
        return "through \(dayFormatter.string(from: end))"
    }
}

#Preview {
    EventPickerView(currentEventId: "demo1815") { _ in }
}
