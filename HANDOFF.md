# TechNexus — handoff

Last updated 17 Aug 2026. The server is deployed and live at `nexus.jerryxf.net`; the iOS app builds and runs.

The single handoff document for this project. `README.md` covers building and running; `Style_iOS.md` covers SwiftUI
conventions. This covers state, blockers, decisions and the things that were expensive to learn.

---

## Where things stand

The app builds and runs on the simulator against frc.nexus demo events. Schedule loads, highlighted teams work, the Live
Activity renders on both the Lock Screen and the Dynamic Island, and Settings persists. The core loop was proven at the
Las Vegas regional against a live event.

The backend is live on Cloud Run at `nexus.jerryxf.net`, fronted by Cloudflare, with Postgres on Neon. CI deploys on
merge to `main`.

It cannot be submitted yet. One blocker is outside the code; the rest is a list of finite tasks.

| Area                   | State                                         |
|------------------------|-----------------------------------------------|
| Schedule tab           | Works, simulator, demo events                 |
| Live Activity          | Lock Screen + Dynamic Island OK on iOS 27 sim |
| Pit tab                | Robot cheat sheet only                        |
| Settings               | Auto-save, reset to defaults, event picker    |
| Stats / TechBotics tab | Commented out in `ContentView`                |
| Server                 | Deployed on Cloud Run at nexus.jerryxf.net    |
| `/batteries`           | Verified against Neon, returns []             |
| Notifications          | Not started                                   |
| Device builds          | Blocked, see below                            |

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

### Deployment, 17 Aug

The server is live at `https://nexus.jerryxf.net`, on Cloud Run in project `technexus-84e3f`, region `us-east1`.
`Backend.kt` points at it and `nexus.raphdf201.net` is retired.

- **Cloud Run** service `technexus-server`. Request-based billing, min 0 / max 4 instances, 1 GiB / 1 vCPU, concurrency
  80, public. Images in Artifact Registry at
  `us-east1-docker.pkg.dev/technexus-84e3f/technexus-server/server`
- **`Application.kt`** reads `PORT` with a 6867 fallback. Cloud Run injects it and health-checks against it; a revision
  listening elsewhere never goes healthy, and the failure message does not mention ports
- **`kotlin { jvmToolchain(21) }`** in `server/build.gradle.kts`. `:server` had no `jvmTarget`, so the fat jar's
  bytecode version was whatever JDK Gradle happened to run on. A JDK 25 build against a `temurin:21-jre` image fails
  with `UnsupportedClassVersionError`, which reads as a corrupt jar
- **`Dockerfile` and `.dockerignore`** at the repo root. Runtime-only image over the fat jar — Gradle never runs inside
  Docker, because `shared` applies `androidKmpLibrary` and any Gradle invocation in this repo therefore needs an Android
  SDK present
- **Postgres is Neon**, AWS `us-east-1`, through the **pooler** endpoint. `DB_URL` carries `prepareThreshold=0`; see
  *Gotchas*. `DB_URL` takes no scheme and no credentials — `Application.kt` prepends `jdbc:postgresql://`
- **Secrets** `NEXUS_API_KEY`, `TBA_API_KEY`, `DB_PASSWORD` in Secret Manager. The service runs as
  `firebase-adminsdk-fbsvc@technexus-84e3f.iam.gserviceaccount.com` — the project was created through Firebase, so that
  is the identity Cloud Run picked up, not the default compute account. It needs
  `roles/secretmanager.secretAccessor` on each secret, granted by hand; the console did not offer it. Broader
  permissions than an HTTP proxy needs; a dedicated runtime account would be tighter
- **Cloudflare Worker** `technexus-proxy`, route `nexus.jerryxf.net/*`. Rewrites the request hostname to the `run.app`
  origin and sets `cf: { cacheEverything: true }`. DNS is a proxied `CNAME` to the same hostname
- **CI deploys.** `build-server.yml` builds the fat jar on every push and, on `main` only, pushes the image, deploys a
  revision, and smoke-tests `/events` through the public hostname. Auth is a service account key in `GCP_SA_KEY`; it
  does not expire and the repo is public, so rotate it after the season or move to Workload Identity Federation. The
  deploy step passes **image only** — passing `env_vars` would replace the whole map rather than merge into it

### Settings, 17 Aug

Save button removed; settings apply as they're made. The screen previously had two contracts on it — the Live Activity
toggle applied instantly through `@AppStorage` while the two text fields waited for a Save tap — with nothing to tell
them apart.

- **Commit timing.** Event picker writes on selection (atomic pick from a finite list; a sheet dismissal is not a focus
  change, so waiting for a blur would never fire). Team number writes on focus loss and on scene phase leaving
  `.active`, never per keystroke — otherwise typing `3990` persists 3, 39, 399, 3990 and any future subscription built
  on it fires four times. Both go through one idempotent `commitTeamNumber()`
- **`.task(id:)` throughout**, not `onChange` — one API that works on iOS 16
- **`resetToDefaults()`** in `Storage.kt`, with a `.confirmationDialog`. It removes the named keys rather than writing
  defaults back, so the getters fall through on their own. Deliberately **not** `Settings.clear()`: on iOS the
  `Settings` instance is backed by `NSUserDefaults.standardUserDefaults`, shared with `@AppStorage` and with keys Apple
  owns. Android has a dedicated `app_settings` file and would be safe either way, but named keys behave identically on
  both
- **`DEFAULT_TEAM_NUMBER` is now `""`.** The app ships to other teams; a default that highlights 3990's robot is worse
  than highlighting nothing. Empty is a valid stored value meaning "no team"
- **`LiveActivityPreference.defaultValue`** added, because `true` was about to be written in three places
- Deleted: `isSaved`, `resetTask`, `hasChanges`, `savedEventId`, `savedTeamNumber`, `save()`, `discard()`, both toolbar
  buttons, both `.animation` modifiers, `ReplaceSymbolTransition`
- **Notifications deliberately absent from the UI.** Toggles that control nothing are placeholder UI under Guideline 4.2

Android still has the Save button and the dead `2026daly` placeholder. `resetToDefaults()` and the empty default are
shared, so Samy gets both for free; the UI is his to mirror.

### iOS and toolchain, 17 Aug

- **Resolved the Swift module blocker.** Two Xcode installs: `xcode-select` pointed at `/Applications/Xcode.app`
  (stable, Swift 6.3.3) while the project was being run from Xcode 27 beta 5 (Swift 6.4). Gradle built the SKIE Swift
  shim with one compiler, Xcode consumed it with the other. `Xcode-beta.app` moved from `~/Downloads` to
  `/Applications`, `xcode-select -s` pointed at it, caches cleared, framework relinked. Full note under *Gotchas*.
- **`@Throws(Throwable::class)` on `getEvents()`** in `Backend.kt`. It was the one backend call designed to throw rather
  than return null, but without the annotation the exception never reached Swift and the picker span forever.
- **Index-keyed the team `ForEach`s** in `MatchCardView.swift` (three sites). `teamList()` maps missing entries to
  `"N/A"`, so `id: \.self` produced duplicate IDs and undefined row behaviour. `ScheduleLiveActivity.swift` already did
  this correctly; the fix was never ported. `TimingCarouselView` and `HighlightTeamsBar` are fine — their collections
  are unique by construction.
- **Confirmed on the iOS 27 simulator:** Live Activity lifecycle, Lock Screen and Dynamic Island rendering, and
  `List<EventSummary>` bridging to `[EventSummary]`.

Still open on the signing config: both Debug configs carry an unqualified `CODE_SIGN_IDENTITY = "Apple Development"`,
which applies to the simulator SDK too and makes Xcode try to resolve team `HWB4Y653YR` for simulator runs. Xcode's
default there is `-` (Sign to Run Locally), needing no account. Harmless today — simulator builds proceed anyway — but
it's noise on every build and wants `[sdk=iphoneos*]` scoping.

Unrelated, for Samy: the Android build warns that AGP 9.0.1 is untested against compileSdk 37.0.

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

Against production at `nexus.jerryxf.net`, 17 Aug:

```
GET /events            200, seven events
GET /event/demo1815    200, includes nowQueuing and actual* times
GET /event/2026daly    404 "2026daly does not exist.", Cache-Control: max-age=15
GET /batteries/all     200 []
cf-cache-status        MISS, then HIT on repeat
```

The 404 / 424 / 500 trio from the old backend is closed. The `[]` is the proof that `createSchema()` ran against Neon
through the pooler — before this the schema had only ever existed in Kotlin.

**Now verified in Xcode.** The app builds and runs on the iOS 27 simulator. `List<EventSummary>` does bridge as
`[EventSummary]`, not `[Any]` — SKIE handled it, so the `List<String?>` → `[Any]` problem is specific to nullable
element types. Live Activity starts and updates, and renders on both the Lock Screen and the Dynamic Island.

**Still not verified:** anything on physical hardware.

---

## Before submission

Ordered by what blocks what.

1. **Pin the deployment target.** All four target configs are still on
   `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)`. Under Xcode 27 beta this resolves to **iOS 17** — it does not track the
   current SDK, and an earlier guess that it followed the beta to iOS 27 was wrong. iOS 17 still silently drops the
   iPhone 8/X and 5th-gen iPad, which is the donated-hardware tier teams actually run, and the value moves between Xcode
   versions. **Pin all six configs to 16.1, not 16.0.** The earlier note said 16.0 on the grounds that "Live Activities
   need 16.1+, so nothing in use is lost" — but that assumed availability guards exist, and they don't.
   `ScheduleActivityAttributes` and `ScheduleLiveActivityManager` use `Activity` and `ActivityAttributes` unguarded,
   both of which are `@available(iOS 16.1, *)`. A 16.0 target fails to compile. Verify with:
   ```
   xcodebuild -showBuildSettings -project TechNexus.xcodeproj \
     -target TechNexus -configuration Release | grep IPHONEOS_DEPLOYMENT_TARGET
   ```
2. **Remove Firebase from the Xcode project** (above)
3. **Android event field** — `composeApp/src/androidMain/.../views/settings/SettingsView.kt:49`
   still has placeholder text `"e.g., 2026daly"`, now a dead event. Samy's file; the picker should be mirrored there
   eventually
4. **FIRST/FRC non-affiliation disclaimer** — nothing in the codebase mentions it. Guideline 5.2.1
5. **Privacy policy** — required by App Store Connect, doesn't exist
6. **App Store Connect metadata** — description, screenshots, privacy labels. Simulator screenshots are acceptable, and
   App Store Connect works today
7. **Confirm on a physical device** once the account resolves
8. **Stable Xcode — resolved as "not a bug", now a scheduling item.** Xcode 26 is not supported on macOS 27 beta; the
   reverse (Xcode 27 beta on macOS 26) is. Confirmed by Apple DTS on the developer forums. Nothing to debug. A beta
   toolchain still cannot be used for App Store submission, so the plan is to finish everything under the beta and
   submit once macOS 27 and Xcode 27 reach general availability — expected at the September event. That also dissolves
   the SKIE swiftmodule problem, which only exists because two Xcodes are installed
9. **Fix the picker's failure copy.** It says "check your connection" when the server is the thing that's down —
   guaranteed confused bug reports from teams on venue wifi. Now testable, since the server can be made to fail

---

## Next up

### Hosting — done, two decisions deferred

The deployed shape is under *Recent work*. Two things were left open on purpose.

**CPU allocation is request-based**, which is correct today and wrong the moment the notification poller exists. Cloud
Run only allocates CPU during request handling, so a `while(true) { poll(); delay() }` loop inside a request-billed
service silently stops a few minutes after the last request — works perfectly in testing, dies overnight. Either
`--min-instances=1 --no-cpu-throttling`, which switches to instance-based billing, or scale to zero and drive the poll
from Cloud Scheduler on its one-minute floor, which is fine for queue status. Decide before writing the poller.

**Artifact Registry has no cleanup policy.** CI tags every image with the commit SHA, so roughly 250 MB accumulates per
merge to `main`. "Keep most recent 5 versions" is one field.

Also open: the `run.app` URL stays publicly reachable and bypasses Cloudflare. For a public read-only proxy that only
means uncached load, which `--max-instances 4` caps. Disabling the default URL is not an option — the Worker targets
that hostname.

### Notifications

Nothing built. **Transport: APNs directly on iOS, FCM on Android.** FCM's iOS path *is* APNs underneath and needs the
same `.p8` key, so neither route avoids the Apple blocker — the auth key comes from the developer portal either way.

**Correction, 17 Aug:** the old reason given here — that FCM lags Apple's Live Activity payload format — stopped being
true in late 2024. FCM supports Live Activities via `apns.live_activity_token`, and `firebase-admin-java` has
`ApnsConfig.Builder.setLiveActivityToken`. The decision still stands, on different grounds:

- **`apns-priority` is not honoured through FCM.** firebase-ios-sdk issue #15648: Live Activity updates sent via FCM
  arrive at priority 10 regardless of the header, which visually alerts and pops the activity out of the Dynamic Island
  on *every* update. For a card that updates on a 15s poll this is disqualifying on its own. Re-check whether it's been
  fixed before committing either way
- **FCM's Live Activity path needs both tokens** — the FCM registration token *and* the ActivityKit token, in one
  message. Two independent rotation schedules, both of which must be current. Direct APNs needs only the ActivityKit
  token
- **It makes Firebase a permanent iOS dependency**, reversing item 2 of *Before submission*, and
  `GoogleService-Info.plist`
  is gitignored — the same trap `google-services.json` set on Android
- FCM in FCM's favour: the server already runs as `firebase-adminsdk-fbsvc@technexus-84e3f`, so `firebase-admin`
  picks up Application Default Credentials with no configuration, and FCM routes sandbox vs production automatically

There is no coherent middle. Direct APNs for Live Activities means `pushy` and the `.p8` are on the server anyway, at
which point sending plain alerts through pushy too is free and Firebase buys nothing on iOS. Splitting alerts to FCM and
activities to APNs pays both costs.

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

**Local notifications — decided against, 17 Aug.** The scheduler is the work, and the scheduler is exactly what push
deletes: once the server diffs the `actual*` keys, the client schedules nothing. It also carries the known hole below.
What survives a switch to push is small and transport-agnostic — `requestAuthorization`, the
`UNUserNotificationCenterDelegate` for foreground presentation and tap routing, and re-reading `notificationSettings()`
on scene phase so the toggles don't lie after someone revokes in iOS Settings. Roughly forty lines, identical under any
transport. Build those when push is built, not before. Original note kept for reference:

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

**Gradle does not track the Swift toolchain.** The Xcode/Swift version is not a declared input to any Kotlin/Native or
SKIE task. With `org.gradle.caching=true` and `org.gradle.configuration-cache=true` both on, switching Xcode versions
changes nothing Gradle can see, so it restores the previous framework from cache without invoking `swiftc` — a green
build producing an artifact the other compiler cannot read. This cost most of 17 Aug. SKIE compiles Swift *into*
`ComposeApp.framework`, so that framework is compiler-version-locked in a way a plain Kotlin/Native framework is not.
Symptom: `Module compiled with Swift X cannot be imported by the Swift Y compiler`, pointing at
`MatchCardView.swift:1:8` — column 8 of line 1 is the module name in `import ComposeApp`, so it is never your Swift
code. Recipe, required on **every** `xcode-select` change:

```bash
./gradlew --stop
rm -rf .gradle/configuration-cache composeApp/build shared/build
rm -rf ~/Library/Developer/Xcode/DerivedData/TechNexus-*
./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64 \
  --no-build-cache --no-configuration-cache --rerun-tasks
```

Confirm with `strings <framework>/Modules/ComposeApp.swiftmodule/arm64-apple-ios-simulator.swiftmodule | grep -i
"swift version"`. **This recurs in reverse when switching back to stable Xcode to archive** — same silent failure,
opposite direction, at the worst possible moment. Both Xcodes also share one DerivedData folder, since the name hashes
the project path.

**Suspend functions need `@Throws` or the continuation leaks.** A Kotlin suspend function without
`@Throws(Throwable::class)` cannot deliver an exception to Swift. It does not crash — the coroutine's exception goes to
`handleUncaughtCoroutineException`, gets printed, and the Swift continuation is **never resumed at all**. `try await`
suspends forever, `catch` never runs, and any `isLoading = false` after it is unreachable. This is the second distinct
cause of an infinite spinner in this codebase; the first was `getEventData` returning nil into a dead `catch`. Identical
from the UI, unrelated mechanisms.

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

**Live Activity attributes are immutable for the activity's lifetime.** `ScheduleActivityAttributes.eventName` was a
copy of a value that changes, which meant switching events left the old key baked in while `content-state` updated from
the new event. The field is referenced nowhere in the extension and `ContentState.eventKey` already carries the same
value mutably, so the fix is to delete `eventName`, not to restart the activity on change. General rule: nothing that
can change belongs in `ActivityAttributes`.

**Status colours are duplicated** between `MatchStatusHelper` (app) and
`LiveActivityFormat` (extension) because the extension doesn't link ComposeApp. Change both. Live Activity card opacity
is `LiveActivityFormat.backgroundTint`.

**Cloudflare Host header rewriting is Enterprise-only.** Origin Rules are documented as "available on all plans", but
the per-feature table is not: Override Host header, Override SNI and Override DNS record are Enterprise; only Override
destination port is on Free. Cloud Run routes by `Host` and 404s anything else, so a custom domain on a Free zone needs
a Worker. Cloud Connector looks like the escape hatch — it modifies the `Host` header automatically and is on Free — but
its GCP support is Cloud Storage buckets only, not Cloud Run.

**The Worker is metered per client request, not per origin request.** Edge caching protects Cloud Run and the frc.nexus
quota and does nothing for Worker invocations, which fire on cache hits too. Workers Free is 100,000 requests/day **per
account**, shared with every other Worker on it. Forty devices polling every 15s over an eight-hour competition day is
roughly 77,000 — fits one team, does not fit two. Workers Paid is $5/month for 10M.

**`cacheEverything` makes JSON cacheable but sets no TTL.** Cloudflare caches by file extension and never caches JSON by
default. With `cacheEverything: true` and no explicit `cacheTtl`, the origin's `Cache-Control` decides, so `/events`
gets 300s and `/event/{key}` gets 15s straight from `Events.kt`. The 404 path inherits `max-age=15` too, because
`call.caching` is set before `proxyNexus` runs — which is what stops a not-yet-published event being negative-cached at
the edge for Cloudflare's default three minutes.

**PgBouncer and pgjdbc disagree about prepared statements.** Neon's pooler endpoint runs transaction pooling; pgjdbc
promotes a statement to a server-side prepared statement after five executions. The two together produce intermittent
`prepared statement "S_3" already exists` — clean in testing, broken under load. `prepareThreshold=0` in `DB_URL`
disables the promotion. Also note `channel_binding` is the libpq spelling and pgjdbc ignores it; the pgjdbc parameter is
`channelBinding`, and it is redundant over TLS.

**Exposed opens a connection per transaction.** `Database.connect(url, ...)` given a URL rather than a DataSource has no
pool, so every `/batteries` call is a fresh TCP+TLS handshake. Against a direct Neon endpoint that exhausts the
connection cap; the pooler absorbs it. A real pool is the eventual answer, but Hikari behaves badly under Cloud Run's
request-scoped CPU, where housekeeper threads freeze between requests. Leave it until the poller forces the issue.

---

## File map

```
README.md                                       overview, modules, config, routes
Style_iOS.md                                    SwiftUI conventions, deployment target
docs/PRIVACY_POLICY_SPEC.md                     content brief for jerryxf.net/technexus/privacy

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

- **Jerry** — iOS, and the backend and its hosting
- **Raphaël** — App Manager on the Apple account. Handover complete; `nexus.raphdf201.net` is retired
- **Samy** — Android/Compose, Statbotics. Can ship server changes by merging to `main` — no GCP access needed

**There is no deadline.** 28 August — Summer Scorcher — is the first chance to run the newer surface (redesigned Live
Activity, event picker, `nowQueuing`, `actual*` times) against a live event, and everything added since Las Vegas is
untested against real data, so it's worth using. It is not a ship date and nothing should be rushed to meet it.

The real gate on submission is the September Apple event: macOS 27 and Xcode 27 reaching general availability is what
makes a submittable toolchain exist. The plan is to have everything finished and verified before then, and submit once
it lands.
