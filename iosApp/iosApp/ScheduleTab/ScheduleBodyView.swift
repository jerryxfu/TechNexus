import ComposeApp
import SwiftUI

struct ScheduleBodyView: View {
    let event: Event?
    let error: String?
    @Binding var highlightedTeams: [String: Color]
    @State private var showPastMatches = false

    var body: some View {
        if let event {
            let currentOnFieldStart = MatchStatusHelper.currentOnFieldStart(
                in: event.matches
            )

            let allDoneMatches = event.matches.filter {
                MatchStatusHelper.isDone(
                    $0,
                    currentOnFieldStart: currentOnFieldStart
                )
            }
            .sorted {
                $0.times.startTime < $1.times.startTime
            }

            let upcomingMatches = event.matches.filter {
                !MatchStatusHelper.isDone(
                    $0,
                    currentOnFieldStart: currentOnFieldStart
                )
            }

            LazyVStack(spacing: 9) {
                if error != nil {
                    staleBanner
                        .padding(.horizontal, 14)
                }

                HighlightTeamsBar(highlightedTeams: $highlightedTeams)
                    .padding(.horizontal, 14)
                // .padding(.bottom, 4)

                // Past matches dropdown with the last completed always visible
                if !allDoneMatches.isEmpty {
                    pastMatchesDropdown(
                        doneMatches: allDoneMatches,
                        currentOnFieldStart: currentOnFieldStart
                    )
                    .padding(.horizontal, 14)
                }

                Divider().padding(.horizontal, 14)

                // Keyed by label, not offset. Nexus labels are unique within
                // an event, and the list reorders on every 15s poll as matches
                // finish so an offset key hands card N's identity to a
                // different match and SwiftUI morphs the two instead of
                // replacing them.
                ForEach(upcomingMatches, id: \.label) {
                    match in
                    MatchCardView(
                        match: match,
                        highlightedTeams: highlightedTeams,
                        currentOnFieldStart: currentOnFieldStart
                    )
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 32)
        } else if let error {
            errorView(error)
        } else {
            loadingView
        }
    }

    // MARK: - Past matches dropdown

    private func pastMatchesDropdown(
        doneMatches: [Match],
        currentOnFieldStart: Int64?
    ) -> some View {
        // Last = most recent completed, older = everything before it
        let lastCompleted = doneMatches.last
        let olderMatches = Array(doneMatches.dropLast())

        return VStack(spacing: 0) {
            // Toggle header (only interactive if there are older matches)
            Button {
                guard !olderMatches.isEmpty else { return }
                withAnimation(.spring(duration: 0.3)) {
                    showPastMatches.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.gray)
                    Text(
                        "\(doneMatches.count) past match\(doneMatches.count == 1 ? "" : "es")"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    Spacer()
                    if !olderMatches.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(
                                .degrees(showPastMatches ? 180 : 0)
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .disabled(olderMatches.isEmpty)

            // Older matches (expanded)
            if showPastMatches && !olderMatches.isEmpty {
                Divider()
                    .padding(.horizontal, 8)
                VStack(spacing: 7) {
                    // Same reasoning as the upcoming list above.
                    ForEach(olderMatches, id: \.label) {
                        match in
                        MatchCardView(
                            match: match,
                            highlightedTeams: highlightedTeams,
                            currentOnFieldStart: currentOnFieldStart
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Last completed match — always visible
            if let lastCompleted {
                Divider()
                    .padding(.horizontal, 8)
                MatchCardView(
                    match: lastCompleted,
                    highlightedTeams: highlightedTeams,
                    currentOnFieldStart: currentOnFieldStart
                )
                .padding(6)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    // MARK: - Empty states

    /// Shown above a schedule we already have when a refresh fails.
    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text("Couldn't refresh \u{2014} showing the last update.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading schedule...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
