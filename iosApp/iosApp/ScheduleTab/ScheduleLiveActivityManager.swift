import ActivityKit
import ComposeApp
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ScheduleLiveActivityManager {
    static let shared = ScheduleLiveActivityManager()

    private var currentActivity: Activity<ScheduleActivityAttributes>?

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
                let attributes = ScheduleActivityAttributes(
                    eventName: event.eventKey
                )
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
            startTimeEpoch: latest.times.estimatedStartTime,
            highlightedTeamsSummary: highlighted,
            eventKey: event.eventKey
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

    private func buildHighlightedSummary(
        event: Event,
        highlightedTeams: [String: Color]
    ) -> [HighlightedTeamInfo] {
        guard !highlightedTeams.isEmpty else { return [] }

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
                    colorHex: hexString(from: color)
                )
            )
        }

        return result.sorted { $0.team < $1.team }
    }

    private func teamList(_ teams: [Any]?) -> [String] {
        guard let teams else {
            // Null alliance list should render as one fallback bar/pill.
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
            return match.times.estimatedQueueTime?.int64Value
                ?? match.times.estimatedOnDeckTime?.int64Value
                ?? match.times.estimatedOnFieldTime
        case "on deck":
            return match.times.estimatedOnDeckTime?.int64Value
                ?? match.times.estimatedOnFieldTime
        case "on field":
            return match.times.estimatedOnFieldTime
        default:
            return match.times.estimatedStartTime
        }
    }

    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else {
            return "#FFFF00"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}

/// Deliberately outside the @MainActor class so the Settings toggle can read the key without actor hops.
// `bool(forKey:)` alone would read an unset key as false, so read the object and default to on.
enum LiveActivityPreference {
    static let key = "liveActivityEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
