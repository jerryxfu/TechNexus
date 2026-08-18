import ComposeApp
import SwiftUI

struct ScheduleView: View {
    @State private var event: Event?
    @State private var error: String?
    @State private var highlightedTeams: [String: Color] = [:]

    /// When this phone last got a response, not when Nexus generated the data.
    /// Drives the header's freshness chip and survives a cold launch via
    /// `CachedSchedule.fetchedAtMs`.
    @State private var lastFetch: Date?

    /// Bumping this cancels and restarts the poll loop, which is how a manual
    /// refresh resets the cadence instead of leaving an automatic poll queued a
    /// second behind it.
    @State private var refreshTick = 0

    @State private var consecutiveFailures = 0
    @State private var lastPersist: Date?

    /// Guards the scene-phase and connectivity tasks, both of which also fire
    /// once on first appearance.
    @State private var didAppear = false

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var network = NetworkMonitor.shared

    /// Base poll interval. Matches `refreshInterval` in `Constants.kt`; the two
    /// are separate because the extension and Android read the Kotlin one and
    /// this file is the only iOS consumer.
    private static let pollSeconds: TimeInterval = 15

    /// Write the schedule to disk at most this often. A successful poll every
    /// 15s over an eight-hour day is 1,900 writes of up to 47 KB; the schedule
    /// only has to be recoverable, not current to the second.
    private static let persistSeconds: TimeInterval = 60

    var body: some View {
        ScrollView {
            ScheduleBodyView(
                event: event,
                error: error,
                highlightedTeams: $highlightedTeams
            )
        }
        .refreshable {
            // Awaiting the fetch is what keeps the system spinner on screen for
            // as long as the request actually takes. Returning immediately and
            // letting the loop pick it up would dismiss the spinner before any
            // data arrived, which reads as "pull to refresh does nothing".
            await refreshNow()
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            ScheduleHeaderView(event: event, lastFetch: lastFetch)
                .background {
                    // Material bleeds up under the status bar, but the header itself stays inside the safe area on every device.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)
                }
        }
        .task {
            // Disk first so the schedule is on screen before the network is even
            // consulted. On a cold launch in a dead zone this is the difference
            // between the last known schedule with live timers and an error page.
            hydrateFromDisk()
            highlightedTeams = HighlightedTeamsStore.load()
            await refreshOnce()
            didAppear = true
        }
        .task(id: refreshTick) {
            await pollLoop()
        }
        .task(id: highlightedTeams) {
            HighlightedTeamsStore.save(highlightedTeams)
            guard let event else { return }
            await ScheduleLiveActivityManager.shared.startOrUpdate(
                event: event,
                highlightedTeams: highlightedTeams
            )
        }
        .task(id: scenePhase) {
            guard didAppear else { return }

            if scenePhase == .active {
                // Returning to the app should not show data from whenever it was
                // backgrounded. The loop's sleep is frozen while suspended, so
                // without this the first update could be a full interval away.
                await refreshNow()
            } else {
                // Leaving is the one moment we know the app may not come back,
                // so force a write regardless of the throttle.
                persist(force: true)
            }
        }
        .task(id: network.isConnected) {
            guard didAppear, network.isConnected else { return }
            await refreshNow()
        }
    }

    // MARK: - Refresh

    /// Fetch immediately, then restart the loop so the next automatic poll is a
    /// full interval away. Used by pull-to-refresh, foregrounding and reconnect.
    private func refreshNow() async {
        await refreshOnce()
        refreshTick &+= 1
    }

    /// Sleeps *first*, then refreshes.
    ///
    /// The old loop refreshed then slept, which meant restarting it, as
    /// `refreshTick` now does, would fire a duplicate fetch immediately. This
    /// order makes a restart mean "the clock starts again from now", which is
    /// what every caller of `refreshNow()` wants. The initial fetch is done by
    /// the `.task` above instead.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(currentInterval))
            guard !Task.isCancelled else { return }
            await refreshOnce()
        }
    }

    /// Backs off after repeated failures. Ten minutes offline at a flat 15s is
    /// forty pointless requests; this makes it about eight. Any reconnect bumps
    /// `refreshTick`, which both restarts the loop and, via a successful fetch,
    /// resets the counter, so recovery is immediate rather than waiting out the current backoff.
    private var currentInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return Self.pollSeconds }
        let steps = min(consecutiveFailures, 3)
        return min(Self.pollSeconds * pow(2, Double(steps)), 120)
    }

    private func refreshOnce() async {
        // NWPathMonitor already knows there's no route. Skipping the request
        // saves a guaranteed timeout, and the failure path below is identical
        // either way.
        guard network.isConnected else {
            // This message is only ever *read* when there's nothing on screen.
            // With an event present, ScheduleBodyView shows its own stale banner
            // and ignores the string. So it must not promise a cached schedule
            // in the one case where there isn't one.
            recordFailure(
                event == nil
                    ? "No connection. Join a network to load the schedule."
                    : "No connection. Showing the last schedule this phone received."
            )
            return
        }

        let eventKey = SettingsManager.shared.settings.getEventId()

        do {
            // getEventData() catches its own exceptions and returns nil (not an error, so nil = error)
            guard
                let newEvent = try await BackendKt.getEventData(
                    eventKey: eventKey
                )
            else {
                recordFailure(
                    "Couldn't load \(eventKey). Check your connection, or the Event ID in Settings."
                )
                return
            }

            event = newEvent
            error = nil
            lastFetch = Date()
            consecutiveFailures = 0
            persist(force: false)

            await ScheduleLiveActivityManager.shared.startOrUpdate(
                event: newEvent,
                highlightedTeams: highlightedTeams
            )
        } catch {
            recordFailure(error.localizedDescription)
        }
    }

    /// Sets the error and increments the backoff counter, but never clears
    /// `event`. A failed refresh marks the data stale; it does not blank the screen.
    private func recordFailure(_ message: String) {
        error = message
        consecutiveFailures += 1
    }

    // MARK: - Persistence

    private func hydrateFromDisk() {
        guard event == nil,
            let cached = ScheduleCacheKt.loadCachedSchedule()
        else { return }

        // A cache written under a different event must not be shown under the
        // current key. Switching events in Settings and relaunching offline
        // would otherwise present the old event's matches under the new name.
        guard
            cached.event.eventKey
                == SettingsManager.shared.settings.getEventId()
        else { return }

        event = cached.event
        lastFetch = Date(
            timeIntervalSince1970: Double(cached.fetchedAtMs) / 1000
        )
    }

    private func persist(force: Bool) {
        guard let event, let lastFetch else { return }

        if !force, let lastPersist,
            Date().timeIntervalSince(lastPersist) < Self.persistSeconds
        {
            return
        }

        ScheduleCacheKt.saveCachedSchedule(
            event: event,
            fetchedAtMs: Int64(lastFetch.timeIntervalSince1970 * 1000)
        )
        lastPersist = Date()
    }
}
