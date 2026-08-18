import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        // Latest match (highest priority match currently in the pipeline)
        var matchLabel: String
        var matchStatus: String
        var redTeams: [String]
        var blueTeams: [String]
        var startTimeEpoch: Int64  // ms

        // Highlighted teams summary "Team: status" pairs
        // Example: ["3990": "On deck", "1815": "Queuing soon"]
        var highlightedTeamsSummary: [HighlightedTeamInfo]

        var eventKey: String

        /// Pre-rendered alliance labels: "RED"/"BLUE" in quals, "A3"/"A?" in
        /// playoffs. Nil only for activities started before these existed.
        ///
        /// Rendered in the app rather than in the extension because the
        /// extension doesn't link ComposeApp, so it can't see `Match.isPlayoff`
        /// or the alliance numbers. Sending the finished string keeps the
        /// playoff rule in one place instead of forking it the way status
        /// colours already are.
        ///
        /// The Dynamic Island uses their presence as the playoff test — see
        /// `ScheduleLiveActivity`.
        var redAllianceLabel: String?
        var blueAllianceLabel: String?

        /// Highlighted teams that didn't fit in the summary above.
        ///
        /// The summary is capped at three so the Dynamic Island doesn't grow an
        /// unbounded stack of chips. Silently dropping the rest would be worse
        /// than the stack, so the surfaces render a "+2".
        var highlightedOverflowCount: Int?
    }

    // No static attributes. Attributes are fixed for the whole life of an
    // activity, so anything that can change must not live here — an `eventName`
    // field used to, and switching events left the old key baked in while
    // `ContentState` updated from the new one. The event key is already carried
    // mutably above.
}

/// Every field added after the first release must be optional.
///
/// `ContentState` is plain `Codable`, and synthesised decoding throws on a
/// missing key even when the property has a default value — only `Optional`
/// tolerates absence. A non-optional addition would fail to decode in any
/// activity that was already running across the update, which on a Lock Screen
/// looks like the card freezing rather than like a crash.
struct HighlightedTeamInfo: Codable, Hashable {
    var team: String
    var matchLabel: String  // e.g. "Qual 15"
    var status: String  // e.g. "On deck"
    var statusEtaEpoch: Int64?  // ms, optional for backward compatibility
    var colorHex: String  // encoded color
}
