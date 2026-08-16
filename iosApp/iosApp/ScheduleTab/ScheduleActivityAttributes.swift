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
    }

    // Static attributes (don't change during the activity lifetime)
    var eventName: String
}

struct HighlightedTeamInfo: Codable, Hashable {
    var team: String
    var matchLabel: String  // e.g. "Qual 15"
    var status: String  // e.g. "On deck"
    var statusEtaEpoch: Int64?  // ms, optional for backward compatibility
    var colorHex: String  // encoded color
}
