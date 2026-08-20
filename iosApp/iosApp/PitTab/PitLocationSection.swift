import ComposeApp
import SwiftUI

/// Where the pits are, at whatever fidelity this event actually publishes.
///
/// Two sections, both always present.
/// Nexus exposes three independent things: a drawn map, team-to-pit addresses, and the team list.
///
/// - **Pit map**: the drawing, or a note that there isn't one.
/// - **Teams**: everyone at the event, with a pit address alongside when known.
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

    /// Everything both sections draw from, resolved once at load.
    struct Loaded {
        let map: PitMap?
        /// Team to pit address, however we came by it.
        let addresses: [String: String]
        /// Every team at the event, numerically sorted.
        let teams: [String]
    }

    enum LoadState {
        case loading
        case loaded(Loaded)
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pitMapSection
            teamsSection
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

    // MARK: - Pit map section

    private var pitMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Pit map", icon: "map")

            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)

            case .failed:
                message(
                    "Couldn't load pit locations. Check your connection, or the Event ID in Settings."
                )

            case .loaded(let data):
                if let map = data.map {
                    mapPreview(map, addresses: data.addresses)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        message("No pit map published for \(eventKey).")
                        myPitRows(addresses: data.addresses)
                    }
                }
            }
        }
    }

    private func mapPreview(_ map: PitMap, addresses: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

            // Outside the button. It reads as a caption on the map, and making a two-line run of text part of the
            // tap target only widens the area where a scroll gesture gets read as a tap.
            mapCaption
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)

            myPitRows(addresses: addresses)
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            PitMapScreen(map: map, highlights: highlights, statuses: statuses)
        }
    }

    /// The hint and the legend as one run of text.
    ///
    /// Concatenated `Text` rather than an `HStack` of pills so it wraps. Each code is the same colour as the canvas draws it in.
    ///
    /// `.foregroundColor` and not `.foregroundStyle`, which on `Text` is iOS 17 and would break the 16.2 floor.
    private var mapCaption: Text {
        var run = Text("Tap to open the full map").foregroundColor(.secondary)

        for entry in PitStatusHighlights.legend {
            run =
                run
                + Text("  ·  ").foregroundColor(Color(.tertiaryLabel))
                + Text(entry.short).foregroundColor(entry.color).fontWeight(.semibold)
                + Text(" \(entry.label.lowercased())").foregroundColor(.secondary)
        }

        return run
    }

    /// "3990 → C12" for each highlighted team that has a pit.
    ///
    /// The single fact most people open this tab for, spelled out rather than left to be found as a coloured
    /// rectangle in a thumbnail-sized preview. Renders with or without a map, because an event that publishes addresses
    /// and no drawing can still answer it.
    @ViewBuilder
    private func myPitRows(addresses: [String: String]) -> some View {
        let mine = Self.sortTeams(highlights.keys.filter { addresses[$0] != nil })

        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(mine, id: \.self) { team in
                    HStack(spacing: 6) {
                        HighlightedTeamPill(
                            team: team,
                            color: highlights[team] ?? .accentColor
                        )

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(.tertiaryLabel))

                        // The same box a team number wears inside a match card's alliance,
                        // in grey because a pit address belongs to neither alliance.
                        TeamPill(
                            team: addresses[team] ?? "",
                            color: Color(.systemGray),
                            compact: false,
                            highlight: nil
                        )
                    }
                }
            }
        }
    }

    // MARK: - Teams section

    @ViewBuilder
    private var teamsSection: some View {
        // Hidden while loading and on failure: the Pit map section above is already showing the spinner or the error,
        // and a section header with nothing under it reads as a bug.
        if case .loaded(let data) = state {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Teams", icon: "person.3")

                if data.teams.isEmpty {
                    message("No teams listed for \(eventKey) yet.")
                } else if data.addresses.isEmpty {
                    teamGrid(data.teams)
                } else {
                    teamAddressList(data.teams, addresses: data.addresses)
                }
            }
        }
    }

    private func teamAddressList(_ teams: [String], addresses: [String: String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(teams.enumerated()), id: \.element) { index, team in
                HStack(spacing: 8) {
                    // A dot rather than recolouring the row:
                    // the team's own highlight colour already owns the text, and two colours on one string reads as a rendering bug.
                    Circle()
                        .fill(statuses[team]?.color ?? .clear)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(team)
                            .font(.body)
                            .fontWeight(
                                highlights[team] != nil || statuses[team] != nil
                                    ? .semibold : .regular
                            )
                            .foregroundStyle(highlights[team] ?? .primary)

                        if let status = statuses[team] {
                            Text(status.label)
                                .font(.caption2)
                                .foregroundStyle(status.color)
                        }
                    }
                    Spacer()

                    // Blank rather than a placeholder for a team the event lists but hasn't given a pit.
                    // "—" in a column of addresses reads as a pit called "—".
                    if let address = addresses[team] {
                        Text(address)
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < teams.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    private func teamGrid(_ teams: [String]) -> some View {
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

    // MARK: - Loading

    /// Fetches the map and the team list always, addresses only when needed.
    ///
    /// A drawn map already carries every team-to-pit pairing in its own boxes, so `/pits` is a fallback for events
    /// that publish addresses without a drawing, two requests in the common case, three in the sparse one. Both
    /// are once-per-event-load rather than polled to save Cloudflare budget.
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

            // A hard failure is the one case worth reporting. `NotPublished` means the event is fine
            // and simply has no drawing, which is a normal state for most events and not an error.
            if result is PitMapFailed {
                state = .failed
                return
            }

            let map = (result as? PitMapAvailable)?.map

            var addresses: [String: String] = [:]
            if let map {
                for pit in map.pits {
                    if let team = pit.team {
                        addresses[team] = pit.address
                    }
                }
            }
            if addresses.isEmpty {
                for entry in try await getPitAddresses(eventKey: eventKey) {
                    addresses[entry.team] = entry.address
                }
            }

            // The endpoint is the authority on who's attending; the addresses are a floor under it,
            // for an event that maps pits without publishing a roster.
            var teams = try await getEventTeams(eventKey: eventKey)
            if teams.isEmpty {
                teams = Array(addresses.keys)
            }

            state = .loaded(
                Loaded(
                    map: map,
                    addresses: addresses,
                    teams: Self.sortTeams(teams)
                )
            )
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

    /// Numeric, not lexicographic.
    ///
    /// Team numbers arrive as strings, and sorting them as strings files 999 after 1815,
    /// which in a list of sixty is the difference between scanning and hunting.
    /// Anything that isn't a plain number sorts to the end rather than being dropped.
    private static func sortTeams<S: Sequence>(_ teams: S) -> [String]
    where S.Element == String {
        teams.sorted { left, right in
            switch (Int(left), Int(right)) {
            case (let l?, let r?):
                return l == r ? left < right : l < r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return left < right
            }
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
