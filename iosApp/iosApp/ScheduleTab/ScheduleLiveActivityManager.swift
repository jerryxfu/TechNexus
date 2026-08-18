import ActivityKit
import ComposeApp
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ScheduleLiveActivityManager {
    static let shared = ScheduleLiveActivityManager()

    private var currentActivity: Activity<ScheduleActivityAttributes>?

    /// How many highlighted teams reach the Live Activity.
    ///
    /// The Lock Screen could hold more, but the Dynamic Island's bottom region
    /// cannot, and one cap in one place beats two surfaces disagreeing. It also
    /// bounds the payload, which stops being cosmetic once these go out as
    /// ActivityKit pushes against a 4 KB budget.
    private static let maxHighlightedTeams = 3

    private init() {
        // Adopt an existing *active* activity so a relaunch doesn't create a duplicate.
        // Ended/stale ones must not be adopted: update() on a dead activity does nothing, and we'd never request a fresh one.
        currentActivity = Activity<ScheduleActivityAttributes>.activities
            .first { Self.isRevivable($0.activityState) }
    }

    /// Start or update the schedule Live Activity. If one is already running, just update it.
    func startOrUpdate(
        event: Event,
        highlightedTeams: [String: Color]
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print(
                "[LiveActivity] Off in iOS Settings > TechNexus > Live Activities"
            )
            return
        }

        guard LiveActivityPreference.isEnabled else {
            await end()
            return
        }

        let state = buildContentState(
            event: event,
            highlightedTeams: highlightedTeams
        )
        guard let state else {
            print("[LiveActivity] No queuing/on-field match — ending activity")
            await end()
            return
        }

        // Let go of an activity the system has already torn down, otherwise we'd keep updating it forever and never start a new one.
        if let activity = currentActivity,
            !Self.isRevivable(activity.activityState)
        {
            print(
                "[LiveActivity] Dropping dead handle (\(activity.activityState))"
            )
            currentActivity = nil
        }

        // If one exists, update; otherwise create
        if let activity = currentActivity {
            await activity.update(
                .init(state: state, staleDate: Self.staleDate())
            )
        } else {
            do {
                let attributes = ScheduleActivityAttributes()
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: Self.staleDate()),
                    pushType: nil
                )
                print("[LiveActivity] Started for \(state.matchLabel)")
            } catch {
                print("[LiveActivity] Failed to start: \(error)")
            }
        }
    }

    /// `.stale` only means the content is past its staleDate. The activity is still live, and updating it revives it.
    // Treating stale as dead ends a working card and starts a duplicate beside it.
    private static func isRevivable(_ state: ActivityState) -> Bool {
        switch state {
        case .active, .stale: return true
        default: return false
        }
    }

    /// Past this point the system marks the card stale rather than showing data that may no longer be true.
    /// Recomputed on every successful update, so it means "five minutes since we
    /// last heard anything", which is the intended reading.
    private static func staleDate() -> Date {
        Date().addingTimeInterval(5 * 60)
    }

    func end() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
    }

    // MARK: - Content state builder

    private func buildContentState(
        event: Event,
        highlightedTeams: [String: Color]
    ) -> ScheduleActivityAttributes.ContentState? {
        guard
            let latest = MatchStatusHelper.latestMatch(
                in: event,
                skippingFinished: true
            )
        else { return nil }

        let redTeams = teamList(latest.redTeams)
        let blueTeams = teamList(latest.blueTeams)

        let highlighted = buildHighlightedSummary(
            event: event,
            highlightedTeams: highlightedTeams
        )

        return ScheduleActivityAttributes.ContentState(
            matchLabel: latest.label,
            matchStatus: statusText(for: latest, in: event),
            redTeams: redTeams,
            blueTeams: blueTeams,
            startTimeEpoch: latest.times.startTime,
            highlightedTeamsSummary: highlighted.shown,
            eventKey: event.eventKey,
            redAllianceLabel: MatchStatusHelper.allianceLabel(
                for: latest,
                isRed: true
            ),
            blueAllianceLabel: MatchStatusHelper.allianceLabel(
                for: latest,
                isRed: false
            ),
            highlightedOverflowCount: highlighted.overflow
        )
    }

    private func statusText(for match: Match, in event: Event) -> String {
        // Must be the full match list: passing [match] made the "superseded by a newer on-field match" check impossible to trigger.
        let currentOnFieldStart = MatchStatusHelper.currentOnFieldStart(
            in: event.matches
        )
        if MatchStatusHelper.isCurrentlyPlaying(
            match,
            currentOnFieldStart: currentOnFieldStart
        ) {
            return "On field"
        }
        return match.status
    }

    /// The highlighted teams whose next match comes soonest, capped, plus how
    /// many were left out.
    ///
    /// Sorted by ETA rather than by team number, because "which of my teams do I
    /// need to care about right now" is a question about time. A team currently
    /// on field sorts to the front for free, its ETA is in the past, with no special case needed.
    ///
    /// Ties break on team number. Teams in the same match share an ETA exactly,
    /// and the card re-renders every fifteen seconds, so without a deterministic
    /// second key they would swap places on screen for no reason.
    private func buildHighlightedSummary(
        event: Event,
        highlightedTeams: [String: Color]
    ) -> (shown: [HighlightedTeamInfo], overflow: Int?) {
        guard !highlightedTeams.isEmpty else { return ([], nil) }

        let currentOnFieldStart = MatchStatusHelper.currentOnFieldStart(
            in: event.matches
        )

        var result: [HighlightedTeamInfo] = []

        for (team, color) in highlightedTeams {
            // Find the next match this team is in (not done)
            let nextMatch = event.matches.first { m in
                let allTeams = teamList(m.redTeams) + teamList(m.blueTeams)
                let notDone = !MatchStatusHelper.isDone(
                    m,
                    currentOnFieldStart: currentOnFieldStart
                )
                return allTeams.contains(team) && notDone
            }

            guard let match = nextMatch else { continue }

            let status: String =
                MatchStatusHelper.isCurrentlyPlaying(
                    match,
                    currentOnFieldStart: currentOnFieldStart
                )
                ? "On field" : match.status

            result.append(
                HighlightedTeamInfo(
                    team: team,
                    matchLabel: match.label,
                    status: status,
                    statusEtaEpoch: statusEtaEpoch(for: match, status: status),
                    colorHex: ColorHex.string(from: color)
                )
            )
        }

        let sorted = result.sorted { lhs, rhs in
            // A team with no ETA at all sorts last rather than first, which is
            // what .max does here — nil means "we don't know when", not "now".
            let left = lhs.statusEtaEpoch ?? .max
            let right = rhs.statusEtaEpoch ?? .max
            if left != right { return left < right }
            return lhs.team < rhs.team
        }

        let shown = Array(sorted.prefix(Self.maxHighlightedTeams))
        let dropped = sorted.count - shown.count
        return (shown, dropped > 0 ? dropped : nil)
    }

    private func teamList(_ teams: [Any]?) -> [String] {
        guard let teams else {
            // Null alliance list should render as one fallback bar/pill.
            // In playoffs this is also what an undecided alliance looks like.
            return ["N/A"]
        }
        var result: [String] = []
        for team in teams {
            result.append((team as? String) ?? "N/A")
        }
        return result
    }

    private func statusEtaEpoch(for match: Match, status: String)
        -> Int64?
    {
        switch status.lowercased() {
        case "queuing soon", "now queuing":
            return match.times.queueTime?.int64Value
                ?? match.times.onDeckTime?.int64Value
                ?? match.times.onFieldTime?.int64Value
        case "on deck":
            return match.times.onDeckTime?.int64Value
                ?? match.times.onFieldTime?.int64Value
        case "on field":
            return match.times.onFieldTime?.int64Value
        default:
            return match.times.hasTiming ? match.times.startTime : nil
        }
    }
}

/// Deliberately outside the @MainActor class so the Settings toggle can read the key without actor hops.
// `bool(forKey:)` alone would read an unset key as false, so read the object and default to on.
enum LiveActivityPreference {
    static let key = "liveActivityEnabled"

    /// One source for the default. `@AppStorage` in Settings, the reader below,
    /// and "Reset to defaults" all read this rather than repeating a literal.
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
