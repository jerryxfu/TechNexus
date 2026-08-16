import ComposeApp
import SwiftUI

struct ScheduleView: View {
    @State private var event: Event?
    @State private var error: String?
    @State private var highlightedTeams: [String: Color] = [:]

    var body: some View {
        ScrollView {
            ScheduleBodyView(
                event: event,
                error: error,
                highlightedTeams: $highlightedTeams
            )
        }
        .safeAreaInset(edge: .top, spacing: 12) {
            ScheduleHeaderView(event: event)
                .background {
                    // Material bleeds up under the status bar, but the header itself stays inside the safe area on every device.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)
                }
        }
        .task {
            await refreshLoop()
        }
        .task(id: highlightedTeams) {
            guard let event else { return }
            await ScheduleLiveActivityManager.shared.startOrUpdate(
                event: event,
                highlightedTeams: highlightedTeams
            )
        }
    }

    // MARK: - Refresh

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func refreshOnce() async {
        let eventKey = SettingsManager.shared.settings.getEventId()

        do {
            // getEventData() catches its own exceptions and returns nil (not and error, so nil = error)
            guard
                let newEvent = try await BackendKt.getEventData(
                    eventKey: eventKey
                )
            else {
                error =
                    "Couldn't load \(eventKey). Check your connection, or the Event ID in Settings."
                return
            }

            event = newEvent
            error = nil

            await ScheduleLiveActivityManager.shared.startOrUpdate(
                event: newEvent,
                highlightedTeams: highlightedTeams
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
