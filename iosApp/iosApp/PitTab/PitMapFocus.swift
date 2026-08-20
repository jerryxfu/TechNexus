import Foundation

/// A pit the map is calling attention to, and when it started doing so.
/// `since` is carried alongside the team rather than being a separate piece of state because the two are only ever meaningful together:
/// the canvas measures its blink phase from it, so a focus without a start time would begin mid-cycle and
/// a start time without a focus would blink nothing. Bundling them makes the pair impossible to desync,
/// and makes re-focusing the *same* team a real change, assigning a new `since` restarts the blink, which is the
/// feedback you want when a second search lands on the pit you were already looking at.
struct PitMapFocus: Equatable {
    let team: String
    let since: Date

    init(team: String, since: Date = Date()) {
        self.team = team
        self.since = since
    }
}
