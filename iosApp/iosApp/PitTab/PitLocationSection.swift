import ComposeApp
import SwiftUI

/// Where the pits are, at whatever fidelity this event actually publishes.
///
/// Nexus exposes three independent things, and events have wildly different
/// amounts of them, so this degrades down a ladder rather than showing one
/// empty state:
///
/// 1. **A drawn map** — geometry, and the richest answer.
/// 2. **Pit addresses** — team to `A1`, with no picture. A separate endpoint
///    that survives when no map was drawn.
/// 3. **The team list** — no locations at all, but confirmation the event has a
///    roster and that yours is on it.
///
/// Only the last rung being empty is a real "nothing here" state.
struct PitLocationSection: View {
    let eventKey: String

    @State private var state: LoadState = .loading
    @State private var showingFullScreen = false
    @State private var highlights: [String: Color] = [:]

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
                PitMapCanvas(map: map, highlights: highlights)
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
            PitMapScreen(map: map, highlights: highlights)
        }
    }

    private func addressList(_ addresses: [PitAddress]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(addresses.enumerated()), id: \.element.team) { index, entry in
                HStack {
                    Text(entry.team)
                        .font(.body)
                        .fontWeight(highlights[entry.team] != nil ? .semibold : .regular)
                        .foregroundStyle(highlights[entry.team] ?? .primary)
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
        // No addresses to pair these with, so a flowing grid reads faster than
        // a one-per-row list of sixty short numbers.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), spacing: 8)],
            spacing: 8
        ) {
            ForEach(teams, id: \.self) { team in
                Text(team)
                    .font(.subheadline)
                    .fontWeight(highlights[team] != nil ? .semibold : .regular)
                    .foregroundStyle(highlights[team] ?? .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                highlights[team]?.opacity(0.18)
                                    ?? Color(.secondarySystemGroupedBackground)
                            )
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

    /// "3990 is in pit C12" — the one fact most people open this tab for, spelled
    /// out so it doesn't depend on finding a highlighted rectangle in a preview
    /// that may be thumbnail-sized.
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

        // Every one of these swallows its own errors and returns a value, so the
        // `catch` below is dead code — it exists because SKIE types suspend
        // functions as `throws`. Same shape as `getEventData`'s callers.
        do {
            let result = try await getPitMap(eventKey: eventKey)

                if let available = result as? PitMapResult.Available {
                state = .map(available.map)
                return
            }

            if result is PitMapResult.Failed {
                state = .failed
                return
            }

            // `NotPublished` — the event is fine, it just has no drawn map.
            // Drop to the next rung rather than reporting an error.
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

    /// The schedule tab's highlighted teams, plus the team number from Settings
    /// if it isn't already one of them.
    ///
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
