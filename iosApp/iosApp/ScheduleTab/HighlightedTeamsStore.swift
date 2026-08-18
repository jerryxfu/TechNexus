import SwiftUI

/// Persistence for the user's highlighted teams.
///
/// These lived in `@State` on `ScheduleView`, which meant they were rebuilt from
/// nothing on every cold launch. Nobody noticed during development because the
/// simulator keeps the process alive; at an event, where the phone is in a pocket
/// between matches and iOS reclaims the app, it means re-entering your teams
/// several times a day.
///
/// Stored in `UserDefaults` rather than alongside the schedule cache: it is a
/// handful of short strings, it is a *preference* rather than fetched data, and
/// it must survive `clearCachedSchedule()`.
///
/// The value is `[team: hexColour]`. Colours come from a fixed six-entry palette
/// in `HighlightTeamsBar`, so the round-trip through hex is lossless in practice.
enum HighlightedTeamsStore {
    /// Also removed by "Reset to defaults" in `SettingsView`. If you rename this,
    /// rename it there too — a stale key would survive a reset and look like the
    /// reset silently failed.
    static let key = "highlightedTeams"

    static func load() -> [String: Color] {
        guard
            let raw = UserDefaults.standard.dictionary(forKey: key)
                as? [String: String]
        else {
            return [:]
        }

        // compactMapValues drops entries whose hex no longer parses instead of
        // substituting a colour, so a corrupt value loses one team rather than
        // silently recolouring it to something the user never picked.
        return raw.compactMapValues { ColorHex.color(from: $0) }
    }

    static func save(_ teams: [String: Color]) {
        guard !teams.isEmpty else {
            // Writing an empty dictionary and removing the key are equivalent on
            // read, but removing keeps `resetToDefaults` and "user cleared their
            // teams" indistinguishable, which is what we want.
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        let raw = teams.mapValues { ColorHex.string(from: $0) }
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
