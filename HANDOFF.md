# TechNexus — handoff

Last updated 16 Aug 2026, at commit `cd1d56e` plus uncommitted server, shared and Settings work.

The single handoff document for this project. `README.md` covers building and running; `Style_iOS.md` covers SwiftUI
conventions. This covers state, blockers, decisions and the things that were expensive to learn.

---

## Where things stand

The app builds and runs on the simulator against frc.nexus demo events. Schedule loads, highlighted teams work, the Live
Activity renders on both the Lock Screen and the Dynamic Island, and Settings persists. The core loop was proven at the
Las Vegas regional against a live event.

It cannot be submitted yet. One blocker is outside the code; the rest is a list of finite tasks.

| Area                   | State                                           |
|------------------------|-------------------------------------------------|
| Schedule tab           | Works, simulator, demo events                   |
| Live Activity          | Renders on simulator. **Never run on hardware** |
| Pit tab                | Robot cheat sheet only                          |
| Settings               | Works; event picker is new and uncompiled       |
| Stats / TechBotics tab | Commented out in `ContentView`                  |
| Server                 | All routes verified locally                     |
| `/batteries`           | Fixed but never run against a real database     |
| Notifications          | Not started                                     |
| Device builds          | Blocked, see below                              |

---

## Blocker — Apple Developer account (owner: Jerry)

**Symptom:** App Store Connect knows team `HWB4Y653YR` and lists Jerry as Account Holder. The developer portal cannot
resolve that same team and returns *"Unable to find a team with the given Team ID 'HWB4Y653YR' to which you belong."*

**Consequences:** no access to Certificates, Identifiers & Profiles; no way to accept the updated Program License
Agreement, which can only be accepted on the developer site; development certificate reported revoked; device builds and
archiving both blocked; **no APNs auth key**, which is what gates all push work. Simulator builds are unaffected, which
is why development has continued.

**Established facts, all verified:**

- Membership purchased 7 May 2026, order `W1499853418`, $136.82 CAD, cleared
- Free Apps Agreement **Active**, 7 May 2026 – 7 May 2027
- Roles: Account Holder + Admin. "Access to Certificates, Identifiers & Profiles" is enabled on the user record
- A team provisioning profile was successfully generated 9 May 2026, including Jerry's iPhone — so the team existed and
  worked briefly
- `developer.apple.com/account` shows a "Join the Apple Developer Program"
  banner; clicking Enroll returns *"already associated with the Account Holder of a membership"*
- "View Membership Details" redirects to the maintenance page while Apple's status page and third-party monitors show
  all systems operational
- No email from Apple since the order confirmation. Nothing in spam

**There is no workaround.** A free Personal Team is not created for an Apple ID that already holds a membership, so
device builds cannot be unblocked with this Apple ID. A second, membership-free Apple ID would get a Personal Team, but
the bundle IDs are registered under `HWB4Y653YR` and would need temporary renaming. Not worth it for one answer.

**Ticket:** submitted under Membership and Account → Program Purchase and Renewal. Lead with the contradiction between
the two systems, not with a claim that the enrollment failed — the membership is demonstrably active and that framing
invites a "your membership is active" close. Ask for the team record to be reconciled, for the License Agreement to be
made acceptable, and for the term to be extended by the time lost since 7 May.

**When it resolves:** Apple may or may not return the same Team ID. If it changes, `DEVELOPMENT_TEAM` in
`project.pbxproj` needs updating.

**What it does not block:** the server, the database schema, hosting, the settings UI, local notifications, App Store
Connect metadata. Only *sending*
pushes and *installing on hardware*.

---

## frc.nexus — what the API actually provides

**`GET /api/v1/events`** returns every event, keyed by event key, with `name`,
`start` and `end`. Requires the API key.

**Nexus only carries current and upcoming events.** Past seasons are purged entirely — there is no historical data and
there never will be. As of 16 Aug there are seven events, all in the future:

| Event        | Name                                  | Dates         |
|--------------|---------------------------------------|---------------|
| `2026azscor` | Summer Scorcher                       | **Aug 28–31** |
| `2026most1`  | Gateway Robotics Challenge            | Sep 11–13     |
| `2026mnros`  | Minnesota Robotics Invitational       | Oct 3–4       |
| `2026mnros1` | Robotics Inspire and Support Everyone | Oct 4–5       |
| `2026cacg`   | CalGames                              | Oct 16–19     |
| `2026wimil`  | SHOUT Robotics Competition            | Oct 17–18     |
| `2026cacc`   | Capital City Classic                  | Oct 23–26     |

Any real event key hardcoded anywhere is a time bomb — it 404s the moment that event ends. Demo events persist. They are
created on frc.nexus and are always named `demo` followed by a number.

**Demo events require a valid API key**, exactly like real ones. `demo1815` with a junk key returns 403. This matters
because it was previously assumed otherwise, and that assumption produced a months-long hunt for an expired key that was
never expired — see *Gotchas*.

**Fields the app receives:**

- `nowQueuing` — the event's own answer for the currently queuing match, e.g.
  `"Practice 10"`. Authoritative, unlike anything reconstructed from `matches`
- `announcements` and `partsRequests` — real Nexus features authored by event volunteers, currently delivered to teams
  only via Slack or Discord opt-in. **Empty on every reachable event, so the schema is unknown and deliberately not
  modelled.** Create a demo event, post an announcement in it, read the shape, then write the data class
- `times.actualQueueTime` / `actualOnDeckTime` / `actualOnFieldTime`

**The actuals are a state machine.** Nexus *omits* each key until that transition really happens:

| Status       | Keys present          |
|--------------|-----------------------|
| Queuing soon | none                  |
| Now queuing  | `actualQueueTime`     |
| On deck      | `+ actualOnDeckTime`  |
| On field     | `+ actualOnFieldTime` |

Status is fully derivable from which keys exist. For the notification poller the diff is **"which key appeared since the
last poll"** — not string comparison against `status`.

---

## Recent work

### Server, this session

- **`Config.kt`** (new). All configuration from the environment: `NEXUS_API_KEY`,
  `TBA_API_KEY`, `DB_URL`, `DB_USER`, `DB_PASSWORD`. All required, validated at startup, missing ones reported together.
  Replaces a five-line `apiKey` file that failed with `IndexOutOfBoundsException`, couldn't be rotated without an SSH
  session, and couldn't be mounted into a container
- **`Nexus.kt`** (new). One proxy helper with honest status mapping. 404 relays as 404; 401/403 becomes 502 because the
  *server's* key is wrong and that isn't the caller's fault; upstream detail goes to the logger
- **`GET /events`** route, cached 5 minutes
- **`createSchema()`** in `Database.kt`. Tables are `internal` so `SchemaUtils`
  can see them
- Database failures propagate — no starting without a database
- `logback.xml` added; logback was a dependency with no configuration
- `Matches.kt` given the same error treatment for The Blue Alliance

### Shared and client, this session

- `Event.nowQueuing`; `MatchTimes.actual*`; `NexusEvent`; `EventSummary`
- **`getEvents()`** in `Backend.kt` — flattens Nexus's map to a sorted
  `List<EventSummary>` in Kotlin, so Android gets the ordering free and Swift avoids a dictionary bridge. **Throws**
  rather than returning null
- Default event ID `2026daly` → `demo1815`

### iOS, this session

- **`EventPickerView.swift`** (new). Sheet with search, sections grouped by start date, demo entry pinned at top with a
  `demo` prefix and number field, checkmark on current selection, distinct loading / failed / empty / no-match states
- Settings' Event ID text field replaced by a picker row
- `saveIcon` had two identical `if #available` arms. Collapsed into a
  `ViewModifier` so there's one `Image` identity instead of one per branch
- `.clipShape(.rect(...))` → `RoundedRectangle(...)`, which was the only thing blocking iOS 16

### Firebase, removed

Five declarations, zero lines of code anywhere in the repo: the `googleServices`
plugin in `androidApp` and the root build file, `firebase-bom` and
`firebase-messaging` in `composeApp`'s `androidMain`, and both version-catalog entries. `google-services.json` is
gitignored, so the plugin made the Android build impossible for anyone without the file.

**Still present in the iOS project** — `FirebaseMessaging` and `firebase-ios-sdk`
in `project.pbxproj` and `Package.resolved`. Remove through Xcode, not by editing the file: Project → Package
Dependencies → `firebase-ios-sdk` → `−`, then app target → General → Frameworks → remove `FirebaseCore`. Then `git diff
project.pbxproj` and confirm nothing moved in `PBXFileSystemSynchronized*`.
`iosApp/iosApp/GoogleService-Info.plist` can leave `.gitignore` at the same time.

### Earlier stabilisation pass

Signing corrected to `Apple Distribution` on both Release configs.
`PrivacyInfo.xcprivacy` added declaring the `NSUserDefaults` required-reason API, without which uploads are rejected
with ITMS-91053. `ITSAppUsesNonExemptEncryption
= NO` added. Unimplemented `UIBackgroundModes` removed. All placeholder copy removed — "Coming soon", empty Pit
sections, "Nothing here yet".

Bugs fixed in that pass, with the reasoning worth keeping: the infinite spinner (`getEventData` returns nil on error, so
the Swift `catch` was dead and `error`
was never set); hardcoded header layout replaced with `.safeAreaInset(edge: .top)`; Live Activity showing stale matches
as "On field"; blank Dynamic Island caused by the extension's folder group being deleted from `project.pbxproj`;
duplicate Live Activity cards because `.stale` was treated as dead when only `.ended` and
`.dismissed` are unrecoverable; frozen blink dot, twice; `ForEach(id: \.offset)`
on a list that reorders every 15 seconds; unresponsive metric/imperial buttons where styling sat outside the `Button`.

The Live Activity was then redesigned: status and time beside the camera, one aligned bottom row of label / alliances /
timer, count-up when a match is overdue,
`icloud.slash` and grey when stale, translucent card. The compact region now always shows the timer — the old "swap to
clock time past an hour out" was removed because `3:45` reads identically as a countdown and as a wall clock.

---

## Verified working

Against a local server on `localhost:6867`, 16 Aug:

```
GET /events            200, seven events
GET /event/demo1815    200, includes nowQueuing and actual* times
GET /event/2026daly    404 "2026daly does not exist."
```

Startup logs `Database connected, schema verified`.

**Not verified:** anything in Xcode. The iOS changes have never been compiled. The specific untested seam is whether
`List<EventSummary>` bridges to Swift as
`[EventSummary]` rather than `[Any]` — SKIE is in the toolchain and usually handles this, but `List<String?>` is already
known to bridge as `[Any]` here.

---

## Before submission

Ordered by what blocks what.

1. **Migrate the domain to `nexus.jerryxf.net` and deploy the new server.**
   `apiUrl` is a hardcoded `const` in `Backend.kt`, so whatever hostname ships in 1.0 is what every user talks to until
   they update — on iOS that's a review cycle. This must also land **before** the app ships, because the picker calls
   `/events`, which doesn't exist on the currently deployed backend. Until then Settings can only reach demo events.
   Needs Jerry's own frc.nexus and TBA keys
2. **Pin the deployment target.** All four target configs are still on
   `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)`, which tracks whatever Xcode is installed. iOS 16.0 is now genuinely
   achievable. Pin all six configs. Verify with:
   ```
   xcodebuild -showBuildSettings -project TechNexus.xcodeproj \
     -target TechNexus -configuration Release | grep IPHONEOS_DEPLOYMENT_TARGET
   ```
3. **Remove Firebase from the Xcode project** (above)
4. **Android event field** — `composeApp/src/androidMain/.../views/settings/SettingsView.kt:49`
   still has placeholder text `"e.g., 2026daly"`, now a dead event. Samy's file; the picker should be mirrored there
   eventually
5. **FIRST/FRC non-affiliation disclaimer** — nothing in the codebase mentions it. Guideline 5.2.1
6. **Privacy policy** — required by App Store Connect, doesn't exist
7. **App Store Connect metadata** — description, screenshots, privacy labels. Simulator screenshots are acceptable, and
   App Store Connect works today
8. **Confirm on a physical device** once the account resolves

---

## Next up

### Hosting

Target shape: Cloudflare for DNS, TLS and edge caching; Google Cloud for compute; Neon or Supabase for Postgres — Cloud
SQL costs more than everything else combined.

**The Cloudflare cache rule is the sleeper win.** `/event/{key}` already carries
`Cache-Control: max-age=15`. A cache rule respecting origin TTL turns forty people polling every 15s into roughly four
origin requests a minute, protecting both the server and the frc.nexus quota. Cloudflare will not cache API-looking
paths unless told to. Don't negative-cache `/events` aggressively — a not-yet-published event shouldn't 404 at the edge
for five minutes.

**Cloudflare Workers is not an option** for this server: JS/WASM runtime, no JVM. Same for D1, Durable Objects and
Queues.

**The Cloud Run gotcha.** Cloud Run only allocates CPU during request handling. A
`while(true) { poll(); delay() }` loop inside a default service silently stops a few minutes after the last request —
works perfectly in testing, dies overnight. Either `--min-instances=1 --no-cpu-throttling`, which switches to
instance-based billing, or scale to zero and drive the poll from Cloud Scheduler on its one-minute floor, which is fine
for queue status. A free-tier `e2-micro` also works but is tight for a JVM at 1GB.

Config is already env-var based, so containerising is mostly a Dockerfile.
`TECHNEXUS_CACHE_DIR` exists because container working directories are often read-only. CI currently only builds
`:server` — no deploy step.

### Notifications

Nothing built. **Transport: APNs directly on iOS, FCM on Android.** FCM's iOS path *is* APNs underneath, needs the same
`.p8` key, and has historically lagged Apple's Live Activity payload format. Neither route avoids the Apple blocker —
the auth key comes from the developer portal either way.

On the JVM: `com.eatthepath:pushy` for APNs, since Ktor's CIO client engine won't do HTTP/2, and `firebase-admin` for
Android.

**The hard part is not the transport.** The server is request-in, response-out with no concept of time passing.
Status-change notifications need it to become stateful:

```
devices               token, platform, created_at, last_seen_at
subscriptions         device_id, event_key, teams[], statuses[]
live_activity_tokens  device_id, token, event_key, created_at
match_state           event_key, match_label, last_status, updated_at
```

- Live Activity tokens are **per-activity**, not per-device. They rotate via
  `pushTokenUpdates` and die with the activity — separate table, separate lifecycle
- `match_state` must be in Postgres. In memory, a redeploy makes every match look like a fresh transition and every
  phone lights up at once
- Delete tokens on `410 Unregistered` from day one
- Diff on the `actual*` keys, not on `status` strings

The poller pays for itself independently: it's also what makes the Live Activity update in the background, and it
replaces N clients hammering the proxy with one upstream fetch per event.

**ActivityKit push updates**, for when the auth key exists:

1. `Activity.request(attributes:content:pushType: .token)`
2. Read the per-activity token from `activity.pushTokenUpdates` (an async sequence), hex-encode it, POST to the backend
   alongside the event key
3. Backend sends to `https://api.push.apple.com/3/device/<token>` with
   `apns-push-type: liveactivity`,
   `apns-topic: net.jerryxf.technexus.push-type.liveactivity`,
   `apns-priority: 10`, body
   `{"aps": {"timestamp": …, "event": "update", "content-state": {…}, "stale-date": …}}`
4. `content-state` keys must match `ScheduleActivityAttributes.ContentState`
   exactly, since it's plain `Codable`: `matchLabel`, `matchStatus`, `redTeams`,
   `blueTeams`, `startTimeEpoch`, `highlightedTeamsSummary`, `eventKey`. Each
   `HighlightedTeamInfo` is `team`, `matchLabel`, `status`, `statusEtaEpoch`,
   `colorHex`
5. Push Notifications capability on the app target, which generates
   `aps-environment`
6. An APNs auth key (`.p8`) from the developer portal → Keys

The payload can carry an `alert` block alongside `content-state`, so one push can both update the card and notify —
better than sending a separate alert push while a Live Activity is already on screen.

**Settings UI shape** (agreed, not built): rename the Live Activity section to Notifications, with subsections separated
by space. Match alerts as one toggle per status for highlighted teams; announcements; then the existing Live Activity
toggle. Request permission on first toggle-on, not at launch, and re-read
`notificationSettings()` on scenePhase change or the toggles will lie after someone revokes in iOS Settings.

The four status strings currently live in `Constants.kt`, `MatchStatusHelper.swift`,
`LiveActivityFormat.swift` and partly `ScheduleLiveActivityManager.swift` — a picker would be a fifth copy. Put the
canonical enum in `shared` so all three platforms and the server agree on wire values.

**Local notifications work today**, with no backend and no Apple account:
`MatchTimes` has an estimate for each of the four statuses, so
`UNCalendarNotificationTrigger` can cover every toggle. Same UI, different source — swap to push later without touching
Settings. Reschedule on every refresh, because the estimates drift; the limitation is that a notification scheduled
while the app was open fires at a stale time if the app is closed when nexus revises.

**Broadcasts** ("lunch is ready in the parking lot") are a different shape:
human-authored, needing an audience and authorisation. Team number in Settings is free text and unauthenticated — fine
for lunch, less fine for "meet at the hotel lobby at 7pm" given the users are minors. A per-team join code closes that
cheaply. Keep the composer server-side for v1; an in-app sender makes the app user-generated content under Guideline 1.2
and invites a reporting-and-blocking requirement on a first submission.

Note Nexus **already has** an announcements system with Slack and Discord delivery, exposed through the API. Event-wide
announcements are close to free once the schema is known and need no authoring UI at all — the volunteers are the
authors. That's separate from team-internal broadcasts.

---

## Gotchas worth remembering

**Nexus purges past events.** No historical data, ever. Any hardcoded real event key is a time bomb.

**Demo events are not unauthenticated.** They need a valid API key like anything else. Assuming otherwise produced a
long hunt for an "expired key" that was never expired: `/event/demo1815` returned 200 and `/event/2026daly` returned 424
on the same afternoon, which looked like the demo event bypassing a dead key. It wasn't. The key was fine and `2026daly`
was a 404 that `Events.kt` had flattened.

**Collapsing upstream statuses destroys information.** One `424` stood in for 404, 401, 403 and 500 for months, with the
real answer going to a `println` on a console nobody read. Relay what actually happened.

**`SchemaUtils.create` is not optional.** `Database.connect` opens a connection and nothing more — it never looks at the
table objects and never issues DDL. `create`
is a no-op for existing tables so it's safe every boot, but it does not alter them; a new column still needs a
migration.

**The Gradle daemon caches the environment.** `./gradlew :server:run` forks a JVM inheriting the *daemon's* environment,
not your shell's, so exports made after the daemon started are invisible. `./gradlew --stop` first, or run
`./server/build/install/server/bin/server` directly.

**SwiftUI shape shorthand silently raises the deployment target.**
`.rect(cornerRadius:style:)` is iOS 17; `RoundedRectangle(cornerRadius:style:)` is iOS 13 and identical. Same for
`.rect`/`Rectangle()`, `.circle`/`Circle()`,
`.capsule`/`Capsule()`. Nothing surfaces until someone pins the target. Full note in `Style_iOS.md`.

**`if #available` widens the availability context for everything inside it.**
`.rect` inside an `if #available(iOS 26.0, *)` block compiles fine against a 16.0 target. Only unguarded uses matter.

**Xcode synchronized folders.** The project uses
`PBXFileSystemSynchronizedRootGroup`, so files on disk are members automatically — no "add to target" step. The flip
side: deleting a file through Xcode can remove the whole folder group. That happened, and the extension silently
compiled nothing for several commits while still building successfully. **Run `git diff` on
`project.pbxproj` after any file operation in Xcode.** A one-line change is normal; twenty deleted lines in the
`PBXFileSystemSynchronized*` sections never is.

**`.onAppear` plus animation.** Mutating state there breaks on re-appearance because the state is already at its target.
A `repeatForever` animation started there also captures the insertion's geometry change and oscillates it forever. Put
`.frame` outside `.animation`, start from `.task` after a short sleep.

**Branching `if #available` around a view breaks symbol effects.** Two branches means two view identities, so SwiftUI
tears down and rebuilds instead of morphing — killing the very effect the branch exists to apply. Put the availability
check in a `ViewModifier` so there's one instance, conditionally modified.

**`Text(timerInterval:)`** reserves layout width for its longest possible value. Without
`.multilineTextAlignment(.trailing)` the digits sit centred in that reserved frame and leave a visible gap.

**Dynamic Island regions.** `.leading` and `.trailing` flank the camera; `.center`
sits *below* it and is roughly cutout-width; `.bottom` is the only full-width region. Three columns that actually align
must live in one region. Corners are rounded at 44pt, so edge content needs padding or it gets clipped. Max height is
144–160pt.

**Button styling** must go inside the label. Applied outside, you've decorated a container the button doesn't know
about — it won't animate, and the tap target is only the text.

**Kotlin `getEventData` catches everything and returns nil.** Swift callers must treat nil as the error; the `catch` is
dead code. `getEvents()` deliberately does not follow this pattern. Fixing `getEventData` is two lines, but Kotlin has
no checked exceptions, so Android call sites will keep compiling and start crashing instead — do it with Samy present.

**Status colours are duplicated** between `MatchStatusHelper` (app) and
`LiveActivityFormat` (extension) because the extension doesn't link ComposeApp. Change both. Live Activity card opacity
is `LiveActivityFormat.backgroundTint`.

---

## File map

```
README.md                                       overview, modules, config, routes
Style_iOS.md                                    SwiftUI conventions, deployment target

iosApp/TechNexus.xcodeproj/project.pbxproj      signing, deployment target, folder groups
iosApp/iosApp/
  ContentView.swift                             three tabs, Stats commented out
  iOSApp.swift                                  entry point, no Firebase
  Info.plist                                    encryption key only
  PrivacyInfo.xcprivacy                         required-reason API declaration
  LiveStatusBadge.swift                         blink badge
  NetworkMonitor.swift                          connectivity
  Shared/SectionTitle.swift                     section header component
  Utils/TimeFormatting.swift                    cached formatters
  ScheduleTab/
    ScheduleView.swift                          15s poll loop, error handling
    ScheduleBodyView.swift                      list, stale banner, empty states
    ScheduleHeaderView.swift                    event key, current match
    HighlightTeamsBar.swift                     team highlighting
    MatchStatusHelper.swift                     latestMatch + status display (app)
    ScheduleActivityAttributes.swift            shared with the extension
    ScheduleLiveActivityManager.swift           activity lifecycle
    Components/MatchCardView.swift              match card
    Components/TeamPill.swift                   team chip
    Components/TimingCarouselView.swift         estimated times
  PitTab/
    PitTabView.swift                            robot info card
    RobotCheatSheet.swift                       model
    RobotCheatSheetView.swift                   sheet, unit toggles
  SettingsTab/
    SettingsView.swift                          event picker row, team, LA toggle
    EventPickerView.swift                       NEW — picker sheet
iosApp/TechNexusExtension/
  TechNexusBundle.swift                         widget bundle
  ScheduleLiveActivity.swift                    Lock Screen + Dynamic Island
  LiveActivityFormat.swift                      formatting, colours, tint

shared/src/commonMain/kotlin/.../shared/
  DataClasses.kt                                Event, Match, MatchTimes,
                                                NexusEvent, EventSummary
  MatchId.kt                                    match key parsing

composeApp/src/commonMain/kotlin/.../
  Backend.kt                                    API client, getEvents
  Storage.kt                                    settings, default event ID
  Constants.kt                                  Android status colours
  schedule/MatchUtils.kt                        shared match logic
  batteries/BatteryManager.kt                   battery tracking
  statbotics/                                   Samy's Statbotics integration
composeApp/src/androidMain/kotlin/.../views/    Android Compose UI

server/src/main/kotlin/.../server/
  Application.kt                                startup, DB connect, HTTP client
  Config.kt                                     NEW — env-var config
  Nexus.kt                                      NEW — proxy + status mapping
  Events.kt                                     /events, /event/{event}
  Matches.kt                                    TBA scores
  Batteries.kt                                  battery CRUD routes
  Database.kt                                   Exposed tables, createSchema
  ServerDataClasses.kt                          TBA response shapes
server/src/main/resources/logback.xml           NEW
```

---

## Ownership

- **Jerry** — iOS, and now the backend and its hosting
- **Raphaël** — App Manager on the Apple account; handing over
  `nexus.raphdf201.net`
- **Samy** — Android/Compose, Statbotics

**The date to work backwards from is 28 August** — Summer Scorcher, and the first chance to run the newer surface
(redesigned Live Activity, event picker,
`nowQueuing`, `actual*` times) against a live event. The core loop already proved itself at Las Vegas; everything added
since is untested against real data.