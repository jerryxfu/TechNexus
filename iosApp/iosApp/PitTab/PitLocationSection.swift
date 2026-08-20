import ComposeApp
import SwiftUI

/// Where the pits are, at whatever fidelity this event actually publishes.
/// Nexus exposes three independent things, and events have wildly different amounts of them, so this degrades down a ladder:
///
/// 1. **A drawn map**: geometry, and the richest answer.
/// 2. **Pit addresses**: team to `A1`, with no picture. A separate endpoint
///    that survives when no map was drawn.
/// 3. **The team list**: no locations at all, but lists the teams present at the event.
/// Only the last rung being empty is a real "nothing here" state.
struct PitLocationSection: View {
    let eventKey: String

    @State private var state: LoadState = .loading
    @State private var showingFullScreen = false
    @State private var highlights: [String: Color] = [:]
    @State private var statuses: [String: TeamStatus] = [:]

    /// Slower than the Schedule tab's 15s.
    /// Only one tab is on screen at a time, so this never runs alongside that poll, but it is still a second caller
    /// against the same Cloudflare budget `CLAUDE.md` flags as tight at two teams.
    /// Queuing statuses turn over on the order of minutes, so half the rate costs nothing you'd notice on a map.
    private let statusRefreshSeconds: UInt64 = 30

    enum LoadState {
        case loading
        case map(PitMap)
        case addresses([PitAddress])
        case teams([String])
        /// The event exists but has published none of the three.
        case empty
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title, icon: icon)

            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)

            case .map(let map):
                mapPreview(map)

            case .addresses(let addresses):
                addressList(addresses)

            case .teams(let teams):
                teamList(teams)

            case .empty:
                message("No pit locations published for \(eventKey) yet.")

            case .failed:
                message(
                    "Couldn't load pit locations. Check your connection, or the Event ID in Settings."
                )
            }
        }
        .task(id: eventKey) {
            await load()

            // Cancelled when the tab goes away, so this stops the moment you switch tabs rather than polling behind the Schedule tab's own.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: statusRefreshSeconds * 1_000_000_000)
                if Task.isCancelled { break }
                await refreshStatuses()
            }
        }
    }

    private var title: String {
        switch state {
        case .teams: return "Teams"
        case .addresses: return "Pit addresses"
        default: return "Pit map"
        }
    }

    private var icon: String {
        switch state {
        case .teams: return "person.3"
        case .addresses: return "list.bullet"
        default: return "map"
        }
    }

    // MARK: - Tiers

    private func mapPreview(_ map: PitMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingFullScreen = true
            } label: {
                PitMapCanvas(map: map, highlights: highlights, statuses: statuses)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    }
            }
            .buttonStyle(.plain)

            if let mine = myPitSummary(in: map) {
                Text(mine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            PitMapScreen(map: map, highlights: highlights, statuses: statuses)
        }
    }

    private func addressList(_ addresses: [PitAddress]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(addresses.enumerated()), id: \.element.team) { index, entry in
                HStack(spacing: 8) {
                    // A dot rather than recolouring the row:
                    // the team's own highlight colour already owns the text, and two colours on one string reads as a rendering bug.
                    Circle()
                        .fill(statuses[entry.team]?.color ?? .clear)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.team)
                            .font(.body)
                            .fontWeight(
                                highlights[entry.team] != nil || statuses[entry.team] != nil
                                    ? .semibold : .regular
                            )
                            .foregroundStyle(highlights[entry.team] ?? .primary)

                        if let status = statuses[entry.team] {
                            Text(status.label)
                                .font(.caption2)
                                .foregroundStyle(status.color)
                        }
                    }
                    Spacer()
                    Text(entry.address)
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < addresses.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    private func teamList(_ teams: [String]) -> some View {
        // No addresses to pair these with, so a flowing grid reads faster than a one-per-row list of sixty short numbers.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), spacing: 8)],
            spacing: 8
        ) {
            ForEach(teams, id: \.self) { team in
                let highlight = highlights[team]
                let status = statuses[team]

                VStack(spacing: 1) {
                    Text(team)
                        .font(.subheadline)
                        .fontWeight(
                            highlight != nil || status != nil ? .semibold : .regular
                        )
                        .foregroundStyle(highlight ?? .primary)

                    if let status {
                        // Wraps rather than shrinks. A shrunk label is unreadable at caption2 and the cell has vertical room to spare.
                        Text(status.label)
                            .font(.caption2)
                            .foregroundStyle(status.color)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    // Fill for "mine", outline for "what's happening" the same two channels the map uses, so the two
                    // surfaces teach the same thing.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            highlight?.opacity(0.18)
                                ?? status?.color.opacity(0.12)
                                ?? Color(.secondarySystemGroupedBackground)
                        )
                        .overlay {
                            if let status {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(status.color, lineWidth: 2)
                            }
                        }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
    }

    /// "3990 is in pit C12", the one fact most people open this tab for, spelled  out so it doesn't depend
    /// on finding a highlighted rectangle in a preview that may be thumbnail-sized.
    private func myPitSummary(in map: PitMap) -> String? {
        let located = highlights.keys
            .compactMap { team -> String? in
                guard let address = map.addressFor(team: team) else { return nil }
                return "\(team) → \(address)"
            }
            .sorted()
        guard !located.isEmpty else { return nil }
        return located.joined(separator: "   ")
    }

    // MARK: - Loading

    private func load() async {
        state = .loading
        highlights = Self.resolveHighlights()

        // Paint from the cache first so the map isn't colourless waiting for the next update.
        // `loadCachedSchedule` deliberately doesn't check which event it holds, so that check belongs here.
        if let cached = loadCachedSchedule(), cached.event.eventKey == eventKey {
            statuses = PitStatusHighlights.derive(from: cached.event)
        }

        await refreshStatuses()

        // Every one of these swallows its own errors and returns a value, so the `catch` below is dead code but
        // it exists because SKIE types suspend functions as `throws`. Same shape as `getEventData`'s callers.
        do {
            let result = try await getPitMap(eventKey: eventKey)

            if let available = result as? PitMapAvailable {
                state = .map(available.map)
                return
            }

            if result is PitMapFailed {
                state = .failed
                return
            }

            // `NotPublished`, the event is fine, it just has no drawn map. Drop to the next rung rather than reporting an error.
            let addresses = try await getPitAddresses(eventKey: eventKey)
            if !addresses.isEmpty {
                state = .addresses(addresses)
                return
            }

            let teams = try await getEventTeams(eventKey: eventKey)
            state = teams.isEmpty ? .empty : .teams(teams)
        } catch {
            state = .failed
        }
    }

    /// Re-derives status colours from a fresh schedule.
    /// Deliberately does not touch `state`. A schedule fetch failing says nothing about whether the pit map loaded,
    /// and blanking a working map because the status colours went stale would be the worst of both.
    private func refreshStatuses() async {
        guard let event = try? await getEventData(eventKey: eventKey) else { return }
        withAnimation(.default) {
            statuses = PitStatusHighlights.derive(from: event)
        }
    }

    /// The schedule tab's highlighted teams, plus the team number from Settings if it isn't already one of them.
    /// Reusing `HighlightedTeamsStore` means the colours match between tabs and
    /// the map answers "where are my alliance partners", not just "where am I".
    private static func resolveHighlights() -> [String: Color] {
        var highlights = HighlightedTeamsStore.load()
        let myTeam = SettingsManager.shared.settings.getTeamNumber()
        if !myTeam.isEmpty, highlights[myTeam] == nil {
            highlights[myTeam] = .accentColor
        }
        return highlights
    }
}
