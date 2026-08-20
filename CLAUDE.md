# TechNexus — technical notes

Last updated 18 Aug 2026. The server is deployed and live at `nexus.jerryxf.net`; the iOS app builds and runs against a
pinned iOS 16.2 deployment target. Schedules refresh correctly, pull-to-refresh works, the app survives losing its
connection, and playoff alliance numbers come through from Nexus.

**This is the working document for Claude, and for any developer who wants the reasoning rather than the summary.**
`README.md` is public-facing — what the project is, how to run the server, how to deploy. `Style_iOS.md` covers SwiftUI
conventions. This file covers state, blockers, decisions, and the things that were expensive to learn. It doubles as the
handoff document when there is one.

Written to be read start-to-finish before touching anything. Most of it exists because something looked like a different
problem than it was.

---

## Working in this repo

- **Read before recommending.** This file and the source in question, not one or the other. Several sections below
  describe behaviour that contradicts what the code appears to do
- **Discuss the design before writing code.** Tradeoffs first, then the change. This is a standing preference, not a
  per-task one
- **Don't build throwaway work.** If a later system deletes a component, skip the component. Local notification
  scheduling was skipped on exactly these grounds — see *Notifications*
- **Verify against the tree, not against memory of the tree.** Jerry pushes after each meaningful change, so pull first.
  Claims in this file that were later disproved are marked as such rather than deleted, because the wrong belief is
  usually the interesting part
- **Two files always change together:** `MatchStatusHelper` (app) and `LiveActivityFormat` (extension) duplicate the
  status colours, because the extension doesn't link ComposeApp. `PitStatusHighlights` is a third consumer but not a
  third copy — its `ranked` table maps display labels to two-letter codes and reads the colours back out of
  `MatchStatusHelper`, so a palette change still lands in exactly two places
- **`git diff project.pbxproj` after any file operation in Xcode.** A one-line change is normal; twenty deleted lines in
  the `PBXFileSystemSynchronized*` sections never is
- **Guard every scripted `pbxproj` edit.** `assert old in s` before each replacement, so a missed pattern fails loudly
  instead of writing a corrupt project file
- **Nothing here is deadline-driven.** Competitions on the calendar are test opportunities, not ship dates

---

## Where things stand

The app builds and runs on the simulator against frc.nexus demo events. Schedule loads, highlighted teams work, the Live
Activity renders on both the Lock Screen and the Dynamic Island, and Settings persists. The core loop was proven at the
Las Vegas regional against a live event.

The backend is live on Cloud Run at `nexus.jerryxf.net`, fronted by Cloudflare, with Postgres on Neon. CI deploys on
merge to `main`.

It cannot be submitted yet. One blocker is outside the code; the rest is a list of finite tasks.

| Area                   | State                                           |
|------------------------|-------------------------------------------------|
| Schedule tab           | Pull-to-refresh, offline cache, 15s poll        |
| Live Activity          | Lock Screen + Island, 3 / 2 team cap            |
| Pit tab                | Robot card, Pit map + Teams sections, legend    |
| Pit map                | Pan/zoom, void overscroll, indicators, search   |
| Settings               | Auto-save, reset to defaults, picker, About     |
| Deployment target      | Pinned to 16.2, six configs, builds clean       |
| Stats / TechBotics tab | Commented out in `ContentView`                  |
| Server                 | Deployed on Cloud Run at nexus.jerryxf.net      |
| `/batteries`           | Verified against Neon, returns []               |
| Playoff alliances      | Server joins Nexus alliances, renders A3 / A?   |
| Offline                | Disk cache, backoff, freshness chip in header   |
| Notifications          | Not started — but Nexus has webhooks, see below |
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

**Status, 18 Aug:** Developer Support has been contacted and their reply suggests this resolves soon. Nothing downstream
is designed around that landing on a particular date.

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

**The OpenAPI spec is the source of truth and it is worth reading.** `https://frc.nexus/api/v1/docs` renders from an
embedded ReDoc spec — the page needs JavaScript, so `curl` returns nothing useful. Extract it from the HTML instead:
the `const __redoc_state = ` blob near the bottom parses as JSON and contains every path and schema. Several things
below were assumed wrong for months and are answered outright in that document.

**Fields the app receives:**

- `nowQueuing` — the event's own answer for the currently queuing match, e.g.
  `"Practice 10"`. Authoritative, unlike anything reconstructed from `matches`
- `announcements` and `partsRequests` — real Nexus features authored by event volunteers, currently delivered to teams
  only via Slack or Discord opt-in. Empty on every reachable event, **but the schemas are documented in the spec**, so
  they no longer need to be reverse-engineered from a live demo event before being modelled
- `times.*` — see below

**Match labels are a documented, closed set:** `Practice N`, `Qualification N`, `Qualification N Replay`, `Playoff N`,
`Final N`. The prefix is a reliable type discriminator, which is what `Match.isPlayoff` relies on. `MatchId.fromLabel`
did not recognise `Playoff` or `Final` at all until 18 Aug — it had an `ELIMINATION` case with a `// TODO : check`
beside it, and Nexus never emits that word — so every playoff and final label parsed to null.

**`replayOf`** marks a replayed match. Without it a replay is indistinguishable from a duplicate in the list.

**Every timestamp in `times` is nullable**, including `estimatedStartTime` and `estimatedOnFieldTime`, which the app
declared non-null until 18 Aug. See *Gotchas* — this could have blanked the entire schedule at a real event.
`scheduledStartTime` is documented as unset for playoffs, which is exactly where real data first differs from a demo.

**`times.actualCommitTime`** is set when the score is committed. It is the only *definitive* end-of-match signal Nexus
gives; `MatchStatusHelper.isDone` previously inferred it from "estimated start plus three minutes is in the past" and
now checks this first, falling back to the buffer heuristic only for events that don't commit promptly.

**The actuals are a state machine.** Nexus *omits* each key until that transition really happens:

| Status       | Keys present          |
|--------------|-----------------------|
| Queuing soon | none                  |
| Now queuing  | `actualQueueTime`     |
| On deck      | `+ actualOnDeckTime`  |
| On field     | `+ actualOnFieldTime` |

Status is fully derivable from which keys exist. For the notification poller the diff is **"which key appeared since the
last poll"** — not string comparison against `status`. The spec warns that **any state transition is possible and some
events skip `Now queuing` entirely**, so the poller must not assume the ladder is climbed one rung at a time.

### Webhooks — there is no need to poll Nexus at all

Found 19 Aug, in the `webhooks` block of the same OpenAPI document. These are requests Nexus makes **to us**; ReDoc
renders them beside the real paths, which is why they read as endpoints we could call. Every actual path is a `GET`.

- **Live event status** — Nexus POSTs the full `EventStatus` body (identical to `GET /event/{key}`) whenever a match
  status changes, a break time changes, a team is added to a playoff alliance, or an announcement or parts request is
  posted or removed.
- **Match status** — registered per team number, POSTs `{eventKey, dataAsOfTime, match}`. Not useful here: registration
  is manual and per-team, which doesn't scale to a public app. The event-level hook carries everything; filter our side.

Registration is a form at `frc.nexus/api`. Requests carry a `Nexus-Token` header for verification. **Whether the
event-level hook is global or per-event is still unknown** — that decides whether setup is one-time or a per-event
chore, and it is only visible in the form.

This removes the poller entirely, and with it the CPU-allocation decision below. Consequences worth holding onto:

- **The payload is a full snapshot, not a delta.** A dropped webhook self-heals on the next one. That makes the whole
  reliability question much less sharp than it first looks.
- **`dataAsOfTime` must gate writes.** The spec warns these fire repeatedly in quick succession, so state writes need to
  be conditional on the incoming timestamp being newer. That replaces "diff since last poll" — `match_state` in Postgres
  is still needed, for ordering as well as flood control.
- **Non-200 responses are not retried, and consistently failing hooks are auto-disabled.** Silent total failure. Return
  200 the instant the token validates and do the work after, so the response never waits on Postgres or APNs.
- **Cold starts are the risk, not CPU.** Either a Cloud Scheduler keepalive (request-billed, so a warm idle instance is
  ~free — about 4,300 vCPU-s/month against a 180,000 free allowance, versus ~2.6M for `--min-instances=1`), or let the
  Cloudflare Worker take the POST, return 200, and forward via `ctx.waitUntil` so Nexus never sees Cloud Run at all.
- **Map edits do not fire a webhook.** Cache TTL is the entire freshness strategy for pit data.

### Pit endpoints

Three more `GET`s the app now uses:

| Path                 | Returns                    | 404 means                                  |
|----------------------|----------------------------|--------------------------------------------|
| `/event/{key}/map`   | Vector pit-map geometry    | event missing **or no map drawn** — common |
| `/event/{key}/pits`  | Team number → pit address  | event missing only; `{}` when nothing set  |
| `/event/{key}/teams` | Flat array of team numbers | event missing only                         |

The three form a fallback ladder: map → addresses → team list. Independent of each other — an event can have addresses
with no drawn map, which is the common case.

**Map coordinate system.** Nexus documents only that 10 units ≈ 1 foot. The rest was verified against the reference
image Nexus publishes with its API examples:

- Origin **top-left, y increases downward**. Pit `A1` at `y = 1020` in a 1300-tall map renders at the *bottom*.
- `angle` in **degrees, clockwise**. An arrow at `-90` renders pointing left.
- `position` is the element **centre**, not its origin.

Both match screen conventions, so `Canvas` needs no axis flip and no angle negation. Convenient but not contractual — if
a map ever renders mirrored, this is the first assumption to re-check.

Elements share one shape (`position`, `size`, `angle`) and differ only in extras: pits carry a nullable `team`, areas
and labels a `label`, arrows a `type` (`single` / `double`) and a `color` constrained to red / blue / purple / gray.
`areas`, `labels`, `arrows` and `walls` are each nullable at the top level; `demo1815` returns `areas: null` outright.
Nexus returns every collection as an object keyed by id, so `PitMap.kt` flattens them into lists the way `NexusEvent`
becomes `EventSummary` — Kotlin maps bridge badly to Swift.

### Alliances

**`GET /api/v1/event/{eventKey}/alliances`** returns playoff alliances as a two-dimensional array. This was assumed not
to exist — the match objects carry no alliance field, and checking a demo event's playoff and final matches showed only
`label`, `status`, `redTeams`, `blueTeams`, `times`, which looked conclusive. It is a separate endpoint.

```json
[
  [
    "3400",
    "1900",
    "200"
  ],
  [
    "2000",
    "2400",
    "900"
  ],
  ...
]
```

Alliance number is **index + 1**. Outer entries may be null (alliance not yet formed), inner entries may be null (slot
not yet picked), and an alliance may have four teams once a backup is in play. The endpoint answers mid-selection, so
partial data is normal rather than exceptional.

**`redTeams` / `blueTeams` are null entirely for an undecided playoff alliance** — not an empty array, the whole field.
So before selection reaches a match, neither the seed nor the teams are known, and there is nothing to fall back to.
That is why the UI shows `A?` rather than reverting to `RED`.

The join is done server-side in `Alliances.kt` and injected into `/event/{key}` as `redAlliance` / `blueAlliance`.
Clients never see the raw array — a `List<List<String?>?>` is precisely the nested nullable-element shape SKIE mangles
into `[Any]`.

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

### Pit map, 19–20 Aug

Six changes to the pit map, in the order they were made. The two canvas fixes are independent of the rest.

- **Status labels are two-letter codes on the map.** A pit is 100 units square and "Queuing soon" measures about the
  same at a readable size, so it was clipped on both sides at every zoom. `TeamStatus.short` carries
  `OF / OD / NQ / QS`, drawn at 22 bold where the full label was 17. `PitStatusHighlights.ranked` became a table of
  `(label, short, raw)` — `derive` still matches on `label`, and `raw` exists only so `legend` can ask
  `MatchStatusHelper` for the colour instead of listing a third copy of the palette. Adding a status is one row, but it
  also lengthens the map legend.
- **Fill/stroke pass split and inset borders** in `drawPits`. See *Gotchas*.
- **Overscroll shadow instead of a permanent vignette.** `edgeShadow` was an always-on fade in
  `systemGroupedBackground`; it is now four black gradients driven by the matching component of `rubberBand`, plus the
  sub-fit zoom deficit added to all four. `minZoom` dropped to 0.8 so pinching out past the fit is a resting state
  rather than pure rubber band, and `fitZoom` is a separate constant for what the toolbar button targets. Zoom
  overscroll rides a `zoomRubber` `.scaleEffect` for the same reason pan overscroll rides `.offset`.
- **Scroll indicators**, drawn rather than native — there is no `ScrollView` here for `showsIndicators` to attach to.
  Per axis, only when that axis has slack, which means nothing at or below the fit. Flash on open, because the screen
  arrives zoomed onto one pit with no gesture behind it.
- **Two fixed sections** in `PitLocationSection`, replacing the map-XOR-addresses-XOR-teams ladder. `LoadState` went
  from five cases to three and `Loaded` carries all three fidelities together. Fetches `/map` and `/teams` always and
  `/pits`
  only when the map is absent or carries no team assignments — a drawn map already holds every pairing in its boxes.
  Teams sort numerically; as strings, 999 filed after 1815. The old `myPitSummary` footnote is now pill → arrow → grey
  `TeamPill` rows, above which sits a concatenated-`Text` caption that doubles as the legend for the two-letter codes.
- **Search**, bottom of the full-screen map. Prefix matching, chip row when ambiguous, auto-centre when exactly one
  match. Both paths only set `focus`; one `.onChange(of: focus)` does the centring, so a tapped chip and a typed match
  behave identically. Clearing is guarded on the marked team no longer matching rather than on the match count — 181 and
  1815 are both real team numbers, so an exact tap can still leave two suggestions.

`HighlightedTeamPill` was lifted out of `HighlightTeamsBar` so the pit rows and the schedule bar share one definition;
the colour dot is what ties a team on the map to a team in the schedule, so two copies drifting would break the thing
the dot is for. The bar passes its delete button through the pill's accessory slot.

Exercised on the simulator against `demo1815` only, which has a map, addresses and a roster. Three branches have not
been run: `PitMapFailed` as distinct from `NotPublished`, the bare team grid (teams present, zero addresses), and the
`/pits`
fallback. Nor has landscape or iPad geometry, where the limiting axis flips and `fitInset`'s asymmetry stops mattering.
Deliberately left alone: `textVisibilityThreshold` is still 0.14 even though two bold characters likely survive further
out than "Queuing soon" did; the legend is preview-only; a team with no pit shows a blank cell rather than a
placeholder, because an em dash in a column of addresses reads as a pit called "—".

### Schedule, offline and alliances, 18 Aug

The session that fixed the frozen schedule. Five items, in the order they were taken.

**1. Nothing was updating.** Schedule, Dynamic Island and Live Activity were all frozen while the console logged
`Updating content for activity …` every 15s. Two stacked causes, neither in Swift:

- Cloudflare's zone-level **Browser Cache TTL** was rewriting every `Cache-Control` to `max-age=14400`. Confirmed on the
  wire: origin values of 15s, 300s, 3600s *and no header at all* all arrived as four hours, including on a route that
  does not exist. Fixed by setting Browser Cache TTL to **Respect Existing Headers**
- `Constants.kt` installed **`HttpCache`**, which obeyed it faithfully and served the same `Event` from memory for four
  hours without a request leaving the device. Every surface froze together because all three read that one object

The edge cache was innocent throughout — it was expiring correctly on its 15s schedule the whole time. `/event/{key}`
now sends `s-maxage=15, max-age=0, must-revalidate`, so shared caches still absorb the load and no client may reuse a
response. `HttpCache` is gone and `HttpTimeout` is installed in its place.

**2. Highlighted teams capped at three**, sorted by soonest ETA rather than team number, with a `+N` chip on both
surfaces. A team on field sorts first for free, since its ETA is in the past. Ties break on team number — teams in the
same match share an ETA exactly, and the card re-renders every 15s, so without a deterministic second key they swap
places for no reason.

**3. Playoff alliance numbers.** `RED` / `BLUE` become `A3` / `A?` in playoffs only, on match cards and the Lock Screen.
In the Dynamic Island they sit *under* the match label as `A3 vs A5` rather than in the alliance rows, which are the
width-critical element in the tightest region on screen. The extension can't reach `Match.isPlayoff`, so the labels are
pre-rendered in the app and travel in `ContentState`. **They are always populated** — `allianceLabel` returns `RED` /
`BLUE` outside playoffs rather than nil, so the row renders on every match type and all three surfaces switch together.
Corrected 18 Aug: this section, `ScheduleActivityAttributes` and `ScheduleLiveActivity` all claimed nil-outside-playoffs
and that the Dynamic Island used their presence as the playoff test. It never did; the `if let` always succeeded.

**4. Pull to refresh.** The poll loop was inverted to sleep-then-refresh, seeded by one initial fetch and restarted by a
`refreshTick` state bump. Pull-to-refresh awaits the real fetch — so the spinner lasts as long as the request — then
bumps the tick, which resets the cadence rather than leaving an automatic poll queued a second behind. The same tick
handles foregrounding and reconnect.

**5. Offline.** The schedule now persists to Application Support and hydrates on launch, so a cold start in a dead zone
shows the last known schedule with live timers instead of an error page. Highlighted teams persist too — they were
`@State` and were lost on every launch. The poll backs off after consecutive failures and skips the request entirely
when `NetworkMonitor` says there is no route. The header carries a freshness chip driven by `TimelineView`, which keeps
counting when nothing else is happening — precisely the offline case it exists to show.

The header also got **shorter** while gaining that chip: ~70pt to ~52pt, by moving to semantic fonts (`.title3`,
`.footnote`), trimming padding, and putting the chip trailing on the event-key line rather than adding a third row.

**Also fixed, found while reading the spec:**

- **`MatchTimes` is fully nullable now.** It declared `estimatedStartTime` and `estimatedOnFieldTime` non-null; one null
  from Nexus would have thrown, been swallowed by `getEventData`, and blanked the whole schedule behind *"Couldn't load
  {event}"*. Call sites moved to a computed `times.startTime` fallback chain, so nothing had to start unwrapping
- **`MatchId.fromShort` off-by-one.** `subSequence(1, length - 1)` dropped the last character as well as the first:
  `q10` parsed as match **1**, `q24` as 2. Single-digit matches were correct, which is why it survived
- **`getTBAKey` returns null for playoffs.** It was building `<event>_em7`, a key TBA has never used, so the request
  404'd and looked like a missing match. TBA keys eliminations by bracket position; there is no arithmetic from Nexus's
  sequential numbering. Now honest, with `Matches.kt` returning a 400 that says so
- **`schedule/MatchUtils.kt` deleted.** Its only contents were `getPlayoffAlliance` and two helpers — 143 lines
  reconstructing alliance numbers from a hardcoded 2023 double-elimination bracket, with a self-admitted placeholder
  bug, called from nowhere. Nexus answers this directly now. Confirmed gone from the tree

Verified by compiling the shared model and all four server files against Kotlin 2.4.10, Ktor 3.5.1 and
kotlinx-serialization 1.11.0, and running 44 behaviour checks: alliance seeding and null handling, backup-robot majority
voting, lossless passthrough of unmodelled keys, the all-null-times decode, and every `MatchId` case above.

### iOS, 18 Aug

- **Dynamic Island match label split across two rows.** `Qualification` on the first, `15` on the second, with the type
  in `.subheadline` secondary and the number keeping the old `.headline`. One string at `.headline` was wide enough to
  scale to 0.7 against the alliance rows and the timer, and the type is identical for eighty consecutive matches while
  the number is the half anyone reads. Split in `LiveActivityFormat.matchLabelParts`, in the extension — it needs
  nothing but the string, unlike the alliance labels, and `ContentState` is about to become the APNs `content-state`
  payload, where every field is a key the server must send and keep in sync. The Lock Screen is unchanged; it has the
  width. Fixed alongside: `compactLabel` took the *last* token as the number, so `Qualification 24 Replay` rendered as
  `QReplay` in the compact region. Now `Q24R`
- **Live Activity and schedule density pass.** Lock Screen: status to `.footnote` and the clock line to `.caption`;
  "Your teams" rows to `.caption`; header-to-alliance gap 8 -> 6, and the divider block nested at 5 so the two sections
  stop taking the outer spacing twice. Dynamic Island: chips to `.caption`, and **capped at two teams**, not three.
  Three fit horizontally but the last one truncates its ETA mid-word, and a cut-off time reads as broken where a `+1`
  reads as deliberate. Capped at the render site, not in `maxHighlightedTeams` — the Lock Screen has room for three and
  shouldn't lose a row to the narrower surface, and that constant also bounds the push payload, which is a different
  concern. The island's overflow count adds the ones it dropped to the ones the manager never sent
- **Schedule density and contrast.** Carousel down ~7pt: the TabView to 22 *and* the dot column's spacing to 2 — four
  dots at 4pt with 3pt gaps is 25pt, so the dots were the taller element and shrinking the TabView alone did nothing.
  Surrounding padding 8 -> 6. Card spacing 8 -> 9. Alliance box fill 0.03 -> 0.05 and stroke 0.12 -> 0.22, its label
  0.7 -> 0.85, and `TeamPill`'s unhighlighted fill 0.08 -> 0.11 and stroke 0.20 -> 0.32. Highlighted values untouched on
  purpose: raising both would have preserved the gap and gained nothing
- **Deployment target pinned to 16.2** across all six configs. Reasoning under *Before submission*. Build is clean at
  16.2, which also confirms nothing in the codebase was quietly depending on a 17+ API
- **Decision: stay on iOS 16.** The question was whether dropping to 17 would buy back design freedom. It would not.
  Every availability check in the app — all five — is `iOS 26.0`, for Liquid Glass; there is not one `iOS 17` guard
  anywhere, so supporting 16 currently costs nothing and a 17 floor would remove no guards. iOS 16 sat near 3.8% share
  in April 2026 and falls further after the September release, but the floor is trivially raised later and cannot be
  lowered once shipped. Counterweight worth knowing: Xcode 27 only debugs on-device from iOS 17 up, so 16.2 is a floor
  that cannot be tested on hardware. Revisit after the account resolves and real devices exist
- **`ScheduleActivityAttributes.eventName` deleted.** See *Gotchas*. Switching events left a stale key baked into the
  activity; the field was read nowhere and `ContentState.eventKey` already carried it mutably. Deletion, not
  restart-on-change — restarting would churn the ActivityKit push token on every event change once push lands
- **Picker failure copy** now branches on `NetworkMonitor.shared.isConnected` instead of always blaming the user's
  connection. Both branches verified by temporarily forcing `loadFailed = true` in `load()`, which is the only way to
  reach the server-down branch, since any real failure that is easy to cause is also an offline failure
- **About footer** in Settings: version and build read from the bundle, credits, `Team 3990 · repo · Privacy policy`
  on one line, then the non-affiliation disclaimer. Styled as a footer rather than a section — no card, no header,
  centred, `.tertiary`, links underlined rather than tinted so the whole block stays one colour. Pinned to the bottom of
  the viewport with `GeometryReader` + `.frame(minHeight:)` + `Spacer`, because a `Spacer` inside a `ScrollView` has
  infinite height to push against and collapses otherwise. `containerRelativeFrame` would replace all of that at 17+
- The GitHub link uses `chevron.left.forwardslash.chevron.right` as a stand-in. **SF Symbols has no GitHub mark**; the
  official Invertocat needs to be added to `Assets.xcassets` as a template image with Preserve Vector Data. A missing
  asset renders as nothing and only logs a warning, so check the simulator after swapping

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

### Server, hosting push (16–17 Aug)

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

### Shared and client, hosting push (16–17 Aug)

- `Event.nowQueuing`; `MatchTimes.actual*`; `NexusEvent`; `EventSummary`
- **`getEvents()`** in `Backend.kt` — flattens Nexus's map to a sorted
  `List<EventSummary>` in Kotlin, so Android gets the ordering free and Swift avoids a dictionary bridge. **Throws**
  rather than returning null
- Default event ID `2026daly` → `demo1815`

### iOS, hosting push (16–17 Aug)

- **`EventPickerView.swift`** (new). Sheet with search, sections grouped by start date, demo entry pinned at top with a
  `demo` prefix and number field, checkmark on current selection, distinct loading / failed / empty / no-match states
- Settings' Event ID text field replaced by a picker row
- `saveIcon` had two identical `if #available` arms. Collapsed into a
  `ViewModifier` so there's one `Image` identity instead of one per branch
- `.clipShape(.rect(...))` → `RoundedRectangle(...)`, which was the only thing blocking iOS 16

### Firebase — removed on Android, retained on iOS

Five declarations, zero lines of code anywhere in the repo: the `googleServices`
plugin in `androidApp` and the root build file, `firebase-bom` and
`firebase-messaging` in `composeApp`'s `androidMain`, and both version-catalog entries. `google-services.json` is
gitignored, so the plugin made the Android build impossible for anyone without the file.

**Still present in the iOS project, and staying there for now** — `FirebaseMessaging` and `firebase-ios-sdk` in
`project.pbxproj` and `Package.resolved`, imported by nothing. This is a decision, not an oversight: the transport
question it was once blocked on is settled, and pulling it out is cosmetic next to what else is open. When it is worth
doing, remove through Xcode, not by editing the file: Project → Package Dependencies → `firebase-ios-sdk` → `−`, then
app target → General → Frameworks → remove `FirebaseCore`. Then `git diff
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

Against the deployed server, 19 Aug:

```
GET /event/demo1815/map      200, 1800x1200, 144 pits, 1 label, 1 arrow, 1 wall, areas: null
GET /event/demo1815/pits     {}      event exists, no addresses assigned
GET /event/2026azscor/map    204     no pit map drawn
```

`demo1815` also confirmed the renderer against real geometry: unassigned pits, a null `areas` block, and a landscape map
on a portrait screen. Nine days from Summer Scorcher, `2026azscor` publishes none of the three, which is the
`.empty` rung and a correct state rather than a bug.

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

**Cache headers, 18 Aug.** After setting Browser Cache TTL to Respect Existing Headers:

```
GET /events            cache-control: max-age=300
GET /event/demo1815    cache-control: max-age=15   (now s-maxage=15, max-age=0 after deploy)
GET /nonexistent-route no cache-control
cf-cache-status        EXPIRED -> HIT -> EXPIRED on a 15s cycle
```

Checking the header on the wire is the fastest way to rule the whole class of problem in or out:

```bash
curl -sSD - -o /dev/null https://nexus.jerryxf.net/event/demo1815
```

**Still not verified:** anything on physical hardware. **And alliance numbers against real data** — demo events have no
alliance structure and aren't on TBA either, so `A?` is the *correct* output there and is indistinguishable from a
broken join. The only way to test properly before Summer Scorcher is to create a demo event on frc.nexus and run
alliance selection in it.

---

## Before submission

Ordered by what blocks what. Struck items are done.

1. ~~**Pin the deployment target.**~~ Done 18 Aug — all six configs on **16.2**.
   `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)` resolved to iOS 17 under the beta Xcode 27. 16.0 was the first guess and
   does not compile. 16.1 was the second and does not compile either. ActivityKit shipped in 16.1, but the API this app
   calls — `Activity.request(attributes:content:pushType:)`, `activity.update(_:)` and
   `activity.end(_:dismissalPolicy:)`, all taking `ActivityContent` — arrived in **16.2** and deprecated the 16.1
   spellings. Nothing in `ScheduleLiveActivityManager` is availability-guarded, so anything below 16.2 is a build error
   rather than a graceful degrade. Verify with:
   ```
   xcodebuild -showBuildSettings -project TechNexus.xcodeproj \
     -target TechNexus -configuration Release | grep IPHONEOS_DEPLOYMENT_TARGET
   ```
2. ~~**Remove Firebase from the Xcode project.**~~ **Deliberately deferred — it stays for now.** `FirebaseMessaging`
   and `firebase-ios-sdk` remain in `project.pbxproj` and `Package.resolved`, and nothing imports either. Removal was
   previously listed as blocked on the transport decision; that decision is made (direct APNs on iOS), and removal is
   still not being done, because it is cosmetic against everything else outstanding. Removal steps are under *Firebase,
   removed* whenever it becomes worth doing. **It is not free while it sits:** clearing DerivedData forces SPM to
   re-resolve `firebase-ios-sdk`, and on 18 Aug that failed and needed Xcode's build cache cleared by hand. A dependency
   nothing imports is still a dependency that can break a clean build, so if a clean build fails oddly, suspect this
   first
3. **Android event field** — `composeApp/src/androidMain/.../views/settings/SettingsView.kt:49`
   still has placeholder text `"e.g., 2026daly"`, now a dead event. Samy's file. The whole Android settings surface is
   scheduled to be translated from the iOS one in a later session, so this closes with that work
4. ~~**FIRST/FRC non-affiliation disclaimer.**~~ Done 18 Aug — in the Settings About footer. **Check the wording against
   *FIRST*'s current trademark guidelines before submitting**; they are specific about italicisation and the registered
   mark, and they change
5. **Privacy policy** — a content brief exists but is **not in this repo**; Jerry keeps it with the personal site work.
   The page goes at `jerryxf.net/technexus/privacy`, and the About footer already links there, so **that link 404s until
   the page is up**. Three decisions were still open in the brief: log retention, Neon row retention, and the App Store
   age rating
6. **App Store Connect metadata** — description, screenshots, privacy labels. Simulator screenshots are acceptable, and
   App Store Connect works today. Screenshots at several device sizes are the long pole
7. **Confirm on a physical device** once the account resolves
8. **Toolchain — not a bug, a calendar item.** Xcode 26 is not supported on macOS 27 beta; the reverse (Xcode 27 beta on
   macOS 26) is. Confirmed by Apple DTS on the developer forums. Nothing to debug. A beta toolchain still cannot be used
   for App Store submission, so the plan is to finish and verify everything under the beta and submit once macOS 27 and
   Xcode 27 reach general availability, expected at the September event. That also dissolves the SKIE swiftmodule
   problem, which exists only because two Xcodes are installed — **do not install another beta after GA**
9. ~~**Fix the picker's failure copy.**~~ Done 18 Aug — branches on `NetworkMonitor.shared.isConnected`. Both paths
   verified in the simulator

---

## Next up

### Hosting — done, two decisions deferred

The deployed shape is under *Recent work*. Two things were left open on purpose.

~~**CPU allocation is request-based**, which is wrong the moment the notification poller exists.~~ **Resolved 19 Aug —
no poller is needed.** Nexus pushes state changes over webhooks, so the server stays request-in/response-out, which is
exactly what request billing is good for and scales to zero out of season. See *frc.nexus → Webhooks*. The remaining
question is cold-start latency on the first webhook after idle, which is a much cheaper problem than always-on CPU.

~~**Artifact Registry has no cleanup policy.**~~ Done. A cleanup policy is in place; CI was otherwise accumulating
roughly 250 MB per merge to `main`.

Also open: the `run.app` URL stays publicly reachable and bypasses Cloudflare. For a public read-only proxy that only
means uncached load, which `--max-instances 4` caps. Disabling the default URL is not an option — the Worker targets
that hostname.

### Notifications

Nothing built. **Transport: APNs directly on iOS, FCM on Android.** The *trigger* is settled as of 19 Aug: Nexus
webhooks, not a poller — see *frc.nexus → Webhooks* for the payload shape, the ordering rule and the auto-disable risk.
Almost none of this work is blocked on Apple. Schema, receiver, `dataAsOfTime`-guarded state writes, diffing and fan-out
are all buildable and testable now with the send stubbed to a log; only the `.p8` transport is gated.

Gaps not covered elsewhere:

- **APNs sandbox vs production.** Direct APNs means picking the host, and the token decides which is valid — development
  builds get sandbox tokens, TestFlight and App Store get production. Store the environment alongside the token, or
  handle `BadDeviceToken`. One of the few real costs of dropping FCM.
- **Two writers to the Live Activity.** The app calls `activity.update()` on its 15s poll today. Once the server pushes,
  they fight. Server should be sole author from the moment a token registers.
- **End of life.** `activityStateUpdates` → `.ended` / `.dismissed` → delete the token server-side, rather than pushing
  into dead tokens until APNs 410s.
- **`pushToStartToken` is 17.2.** At the 16.2 floor the server cannot *start* an activity — someone must open the app at
  the venue. Probably the strongest argument that will ever exist for raising the floor.
- **Skipped rungs.** Fire only the terminal state reached, never the ladder inferred; never fire on a backwards
  transition, since Nexus revises.
- **Time-sensitive interruption level.** Exactly the use case — noisy venue, phone in a pocket. Check whether the
  entitlement needs requesting.
- **The Worker request budget does not improve.** Push moves Live Activity updates off the client, but the schedule tab
  still polls at 15s, so the 77k/day figure stands and two teams still don't fit. FCM's iOS path *is* APNs underneath
  and needs the same `.p8` key, so neither route avoids the Apple blocker — the auth key comes from the developer portal
  either way.

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

## Open — the jumping dot

Seen twice, reproduced never. Once the status dot inside a match card's `LiveStatusBadge` moved **up and down**; once
the header's dot moved **left and right**. Both dots run a `repeatForever(autoreverses: true)` opacity animation that is
by definition always in flight, and both sit at the trailing end of a row whose width depends on text beside them.

The hypothesis is not that the animation is wrong. It is that **an existing view was handed new content instead of being
replaced**, so a layout delta became something to animate rather than something to swap. Two places did that:

- `ScheduleBodyView` keyed both match lists with `ForEach(id: \.offset)`. The list reorders on every 15s poll as matches
  finish, so card N's identity moves to a different match. Now keyed on `match.label`, which Nexus guarantees unique
  within an event — including `Qualification 24` vs `Qualification 24 Replay`. **The team `ForEach`s keep `\.offset`
  deliberately** and must not be changed: `teamList()` maps missing entries to `"N/A"`, so those strings are not unique
- `ScheduleHeaderView`'s status line kept one identity as `latest` advanced, so `Qualification 9` -> `Qualification 10`
  widened an existing row and slid the dot along it. Now `.id(latest.label)`

Both changes are correct independently of the bug, which is the only reason they were made without a reproduction.
**Neither is confirmed to fix it.** If it recurs, the next thing to rule out is the badge's own insertion: it is behind
`if !isFarFromQueuing`, which is computed from `Date()` at render time and can therefore flip on a poll tick.

Fastest way to force the conditions: point at a demo event, highlight enough teams that the list reorders, and watch a
card at the boundary as a match completes.

---

## Gotchas worth remembering

**Nexus purges past events.** No historical data, ever. Any hardcoded real event key is a time bomb.

**A CDN can rewrite your `Cache-Control` and there is no sign of it in your code.** Cloudflare's zone-level Browser
Cache TTL overrides what the origin sends — every value, and it *adds* one where the origin sent none. This froze the
entire app for four hours at a time while the poll loop, the Live Activity updates and the logs all looked perfectly
healthy, because the only broken thing was that no request was being sent. Check the wire before reading code:
`curl -sSD - -o /dev/null <url>`. The setting lives under Caching → Configuration; Cache Rules can also set it.

**Do not install `HttpCache` in a polling client.** Everything this app fetches is either live or mutable, so RFC 7234
caching has nothing to offer it and one bad upstream header turns it into a four-hour freeze. Worse, a client TTL equal
to the poll interval leaves no margin: a pull-to-refresh landing mid-window is answered from cache, and the spinner
spins over unchanged data *intermittently*. Express the intent in headers instead — `s-maxage` for shared caches,
`max-age=0` for private ones. That also reaches `NSURLSession`'s own disk-backed `URLCache`, which `commonMain` cannot
configure.

**Nexus types every timestamp as nullable and means it.** `kotlinx.serialization` throws on a null for a non-null field,
`getEventData` swallows the exception and returns nil, and the app reports *"Couldn't load {event}. Check your
connection, or the Event ID in Settings"* — pointing the user at two things that are both fine. **One null field
anywhere in the payload blanks the entire schedule.** Demo events populate everything, so this is invisible in testing;
`scheduledStartTime` is documented as unset for playoffs. Model the wire faithfully and put the convenience in computed
properties.

**`buildMap` fails to infer when there is nothing outside it to anchor `K` and `V`.** Assigning it to an untyped `val`
whose `catch` branch `return`s leaves the builder with no expected type, and Kotlin cannot propagate constraints from a
`put` nested two lambdas deep. The reported errors are misleading in a specific and expensive way: once `K` and `V`
become error types, the compiler lists receiver mismatches against **`kotlinx.io.Source`** extensions that are merely on
the classpath via Ktor, so a JSON file reports errors about byte streams. When an error names `Source` in code that
touches no I/O, look upward for a failed inference. Explicit `mutableMapOf<K, V>()` removes the trap.

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
the project path, and `Index.noindex` inside it produces the duplicate "Also imported here" lines.

Two things about running that recipe. Quit Xcode first — it recreates DerivedData mid-delete otherwise. And **a correct
rebuild is fast**, around 16 seconds, because `~/.konan` is untouched and only your own code recompiles, so judge it by
the SKIE warnings appearing in the output rather than by the clock: a restored cache entry prints nothing.

**This whole class of problem is temporary.** It exists only because two Xcodes are installed. It disappears when macOS
27 and Xcode 27 reach general availability and the beta comes off the machine — see item 8 of *Before submission*. Do
not install another beta after that.

**Xcode 27 beta rewrites `project.pbxproj` cosmetically.** It renames `PBXFileSystemSynchronizedBuildFileExceptionSet`
comments to descriptive form and drops empty `explicitFileTypes = {}` / `explicitFolders = ()` entries. This is
*benign* — not the folder-group corruption that guarded edits exist to catch. What matters is that
`membershipExceptions` still lists `ScheduleTab/ScheduleActivityAttributes.swift` for the extension target; if that
disappears, the extension loses the shared `ContentState` and fails to build.

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

**A 404 you relay and a 404 Ktor invents look identical to the client.** `/event/{key}/map` legitimately 404s when an
event has no pit map, so the client treated any 404 as "no map published" — and then said exactly that while the real
cause was that the route hadn't been deployed yet. The tell on the wire is the body: a relayed Nexus 404 carries a
message, Ktor's route-miss carries zero bytes. Fixed by answering **204** for "no map", leaving 404 to mean what it
always meant. Same shape as the `2026daly` mistake: two different failures that looked the same.

**A negative answer needs a shorter TTL than a positive one.** The 204 above inherited the map route's `max-age=300,
s-maxage=900` and hid a pit map for the whole window after a volunteer drew one. It now gets 30s. "Nothing here yet" is
by definition the state most likely to change while someone is looking at it.

**`withAnimation` does not animate anything a `Canvas` draws.** SwiftUI interpolates animatable values in the *view
tree*; a value read inside a `Canvas` closure isn't one — the closure just re-runs once at the final value. Wrapping a
pan assignment in `withAnimation` produced an instant snap that looked like a broken gesture. Fix: keep the value fed to
the canvas clamped, and put the animated part on a real modifier (`.offset`) alongside it.

**Kotlin `List<String?>` arrives in Swift as `[Any]`.** The nullable element type doesn't survive the ObjC bridge, so
`match.redTeams` needs `(entry as? String)` rather than optional-pattern unwrapping. `MatchCardView` and
`ScheduleLiveActivityManager` already did this; anything new reading teams must too.

**`Color.tertiary` does not exist.** `.primary` and `.secondary` are static members on `Color`; `.tertiary` is only a
`HierarchicalShapeStyle`, so it works in `.foregroundStyle(.tertiary)` and fails wherever a `Color` is required. Use
`Color(.tertiaryLabel)` there.

**Nested Kotlin classes have two Swift spellings.** A nested `sealed class` subclass exports as `OuterInner` with an
`NS_SWIFT_NAME(Outer.Inner)` alias, and which one Swift accepts depends on how SKIE is handling sealed classes. Declare
them top-level (`PitMapAvailable`, not `PitMapResult.Available`) and there is only one spelling.

**Aspect-fitting twice is invisible until you try to pan.** `PitMapCanvas` fitted the map to its own aspect ratio *and*
inside `draw`, so the full-screen viewer's pan clamping was computing against a viewport the canvas never received. The
canvas now takes a `fitsAspectRatio` flag and exposes `fitScale` statically so both agree by construction.

**`withAnimation` cannot reach a `Canvas`, and `TimelineView` is the way in.** The existing note is that a value read
inside a draw closure is not in the view tree, so wrapping its assignment in `withAnimation` re-runs the closure once at
the final value. The other half is what to do instead. For *springback*, split the animated part out as a real
modifier —
`pan` stays hard-clamped and feeds the canvas, while `rubberBand` rides an `.offset` and `zoomRubber` a `.scaleEffect`.
For a *continuous* animation there is nothing to split, so drive it from a clock:
`TimelineView(.animation(minimumInterval:paused:))` hands the draw closure a `Date` and the phase becomes arithmetic.
Attach the schedule unconditionally and toggle `paused` — an `if` around the view is two identities and tears the canvas
down and rebuilds it, which in `PitMapScreen` means mid-gesture.

**The same trap wears a second disguise: gradient colours.** `LinearGradient(colors: [void.opacity(x), ...])` rebuilds
once at the final value and *snaps*, while the `.offset` it is describing springs over 0.35s. A gradient is not
animatable; `.opacity` is. Build the gradient from fixed colours and put the varying part in an `.opacity` modifier.
Applies to any value baked into a non-animatable initializer, not just gradients.

**Draw order inside a `Canvas` is data order, which is somebody else's alphabet.** `demo1815`'s pits are 100 units
square on a 100-unit grid — edge to edge, no gutter — and Nexus keys them in an object, so the flattened order is `A1, A10, A11,
A12, A2`. Filling and stroking each pit in one loop therefore let a neighbour's fill land on the border of the pit next
to it, and *which* neighbour won came down to sort order: a highlight read as above the grid lines in some places and
under them in others. `drawPits` resolves every pit's colours up front into `StyledPit`, then runs separate passes —
fills, plain borders, emphasised borders, labels, focus ring. Resolving first is what makes the split safe; three passes
each recomputing their own answer would be a worse version of the same bug. Borders also inset by half their width
(`.strokeBorder` semantics, not `.stroke`), so a 6pt ring cannot reach into the next pit at all.

**One margin, one function.** `PitMapScreen.contentBox` is the viewport less `fitInset` on every side, and the fit, the
pan clamp and the scroll indicators must all measure against it. Every combination of *some* of them has now been
shipped and been wrong: inset on all three plus an always-on vignette read as no padding, because the vignette sat
inside the inset and ghosted the map before it reached the margin; inset on none made "fit to screen" jam the map
against both bezels; inset on the fit alone made the margin vanish the moment you zoomed in. Indicators measuring
against the raw viewport park the thumb a margin's width early. `fitScale` takes the inset as a *parameter* rather than
callers pre-shrinking `viewSize`, because the canvas still has to draw across the full surface — fit into a smaller box
and draw into one too, and no zoom level can reach the margin.

**"Queuing soon" is Nexus's default, not a signal.** Measured on `demo1815` it spans 0 to 87 minutes out and covered 72
of 144 pits. `MatchStatusHelper.queuingHorizonMs` is the single horizon both the schedule badges and the pit map apply —
it was 10 minutes in `MatchCardView` while the comment above it said 30, so nobody had looked at that number in a while.

---

## File map

```
README.md                                       public overview, server config, routes, deploy
CLAUDE.md                                       this file
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
  Utils/ColorHex.swift                          NEW — Color <-> hex, app target
  ScheduleTab/
    ScheduleView.swift                          poll loop, pull-to-refresh,
                                                disk hydration, backoff
    ScheduleBodyView.swift                      list, stale banner, empty states
    ScheduleHeaderView.swift                    event key, match, freshness chip
    HighlightTeamsBar.swift                     team highlighting
    HighlightedTeamsStore.swift                 NEW — persists highlighted teams
    MatchStatusHelper.swift                     latestMatch, status, alliance labels
    ScheduleActivityAttributes.swift            shared with the extension
    ScheduleLiveActivityManager.swift           activity lifecycle, 3-team payload cap
    Components/MatchCardView.swift              match card
    Components/TeamPill.swift                   team chip (also the pit-address box)
    Components/HighlightedTeamPill.swift        NEW — dot + number, shared with the pit map
    Components/TimingCarouselView.swift         estimated times
  PitTab/
    PitTabView.swift                            compact robot row + pit section
    RobotCheatSheet.swift                       model
    RobotCheatSheetView.swift                   sheet, unit toggles
    PitLocationSection.swift                    Pit map + Teams sections, legend, pit rows
    PitMapCanvas.swift                          Canvas renderer, fitScale, draw passes
    PitMapScreen.swift                          full screen, pan/zoom, void, indicators, search
    PitMapFocus.swift                           NEW — searched pit + blink start
    PitStatusHighlights.swift                   TeamStatus, short codes, legend
  SettingsTab/
    SettingsView.swift                          event picker row, team, LA toggle
    EventPickerView.swift                       NEW — picker sheet
iosApp/TechNexusExtension/
  TechNexusBundle.swift                         widget bundle
  ScheduleLiveActivity.swift                    Lock Screen + Island, 2-team island cap
  LiveActivityFormat.swift                      formatting, colours, tint, label splitting

shared/src/commonMain/kotlin/.../shared/
  DataClasses.kt                                Event, Match, MatchTimes,
                                                NexusEvent, EventSummary
  MatchId.kt                                    match key parsing
  PitMap.kt                                     NEW — map geometry, wire → flat

composeApp/src/commonMain/kotlin/.../
  Backend.kt                                    API client, getEvents
  PitBackend.kt                                 NEW — pit map / addresses / teams
  Storage.kt                                    settings, default event ID
  ScheduleCache.kt                              NEW — last schedule on disk
  Constants.kt                                  HTTP client, Android status colours
  batteries/BatteryManager.kt                   battery tracking
  statbotics/                                   Samy's Statbotics integration
composeApp/src/androidMain/kotlin/.../views/    Android Compose UI

server/src/main/kotlin/.../server/
  Application.kt                                startup, DB connect, HTTP client
  Config.kt                                     env-var config
  Nexus.kt                                      proxy + status mapping
  Alliances.kt                                  NEW — playoff alliance join
  Events.kt                                     /events, /event/{event}
  Pits.kt                                       NEW — /map, /pits, /teams
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
Activity, event picker, `nowQueuing`, `actual*` times, playoff alliance numbers, offline behaviour) against a live
event, and everything added since Las Vegas is untested against real data, so it's worth using. Playoff alliances in
particular cannot be meaningfully tested any other way short of building a demo event and running selection in it. It is
not a ship date and nothing should be rushed to meet it.

The real gate on submission is the September Apple event: macOS 27 and Xcode 27 reaching general availability is what
makes a submittable toolchain exist. The plan is to have everything finished and verified before then, and submit once
it lands.
