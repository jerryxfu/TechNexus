# TechNexus

A companion app for FRC teams: match schedule, queue status, and pit tools, built on live data
from [Nexus](https://frc.nexus).

Kotlin Multiplatform with a native SwiftUI layer on iOS and Compose on Android.

*TechNexus is an independent project and is not affiliated with, endorsed by, or sponsored by *FIRST*.*

## Modules

Five build units in one repo. They share code but ship independently — nothing coordinates their release.

| Module       | Output                  | Notes                                                                                                                                          |
|--------------|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared`     | iOS framework + JVM jar | Data classes and JSON config. The wire contract: server and clients compile against the same `@Serializable` types, so the format can't drift. |
| `composeApp` | KMP library             | Client logic — API calls, settings storage. Depends on `shared`.                                                                               |
| `androidApp` | `.apk` / `.aab`         | Android UI.                                                                                                                                    |
| `iosApp`     | `.ipa`                  | SwiftUI app and the Live Activity extension. Built by Xcode, not Gradle.                                                                       |
| `server`     | fat jar                 | Ktor service behind `nexus.jerryxf.net`. Depends on `shared`, not on `composeApp`.                                                             |

Only four of those are Gradle modules; `iosApp` is opened directly in Xcode.

## Data sources

| Source            | Used for                                                  | Notes                                                                                                                                                                       |
|-------------------|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| frc.nexus         | Event list, live match and queue status, timing estimates | Requires an API key, including for demo events. Only carries current and upcoming events — past seasons are purged, so a hardcoded real event key 404s once the event ends. |
| The Blue Alliance | Match scores                                              | Requires an API key.                                                                                                                                                        |

The clients never call either directly; both go through the server, which holds the keys.

## Notifications

Not built yet. When they are, the transport is **APNs directly on iOS, FCM on Android**, triggered by **Nexus webhooks**
rather than by polling.

Nexus POSTs the full `EventStatus` body — the same shape as `GET /event/{key}` — whenever a match status changes, a
break time changes, a team joins a playoff alliance, or an announcement or parts request is posted or removed. Webhook
URLs are registered at [frc.nexus/api](https://frc.nexus/api) and requests carry a `Nexus-Token` header for
verification. Because the payload is a full snapshot rather than a delta, a dropped delivery self-heals on the next one;
because deliveries are not retried and consistently failing hooks are disabled automatically, the receiver returns 200
as soon as the token validates and does its work afterwards. Ordering is not guaranteed, so state writes are gated on
`dataAsOfTime`.

Routing iOS through FCM would buy nothing and cost something. FCM's iOS transport *is* APNs underneath, so it needs the
same `.p8` auth key either way and avoids none of the Apple Developer account setup. It does support Live Activities
these days, via `apns.live_activity_token` — but **`apns-priority` is not honoured through it**
([firebase-ios-sdk#15648](https://github.com/firebase/firebase-ios-sdk/issues/15648)): updates arrive at priority 10
regardless of the header, which alerts the user and pops the activity out of the Dynamic Island on *every* update. For a
card that updates on a 15-second cadence that is disqualifying on its own. It also needs two tokens per message, the FCM
registration token and the ActivityKit token, on independent rotation schedules, where direct APNs needs only the
latter.

Once `pushy` and the `.p8` are on the server for Live Activities, sending plain alerts through the same path is free, so
Firebase earns nothing on iOS. On the JVM that means `com.eatthepath:pushy` for APNs — Ktor's CIO client engine won't do
HTTP/2 — and `firebase-admin` for Android.

Firebase was previously linked on both platforms with no code behind it, which made `google-services.json` a build
requirement for a file nobody had. It is gone from Android and from the Gradle build. It is still declared in the Xcode
project and imported by nothing; see `CLAUDE.md`.

## Server config

All configuration comes from the environment. Every variable below is required, and a missing one fails at startup
naming all of them at once.

| Variable        | Purpose                                                     |
|-----------------|-------------------------------------------------------------|
| `NEXUS_API_KEY` | frc.nexus API key, from https://frc.nexus/api               |
| `TBA_API_KEY`   | The Blue Alliance key, for match scores                     |
| `DB_URL`        | Postgres host and database, e.g. `localhost:5432/technexus` |
| `DB_USER`       | Postgres user                                               |
| `DB_PASSWORD`   | Postgres password                                           |

Two optional ones. `TECHNEXUS_CACHE_DIR` moves the server's *outbound* HTTP cache — its own calls to Nexus and TBA — off
the working directory, which a container often mounts read-only. `PORT` defaults to 6867; Cloud Run injects it and
health-checks against it.

`DB_URL` takes no scheme and no credentials; the server prepends `jdbc:postgresql://`. Against a pooled endpoint such as
Neon's, append `?prepareThreshold=0`.

## Running locally

Postgres, once:

```
docker run -d --name technexus-db -p 5432:5432 \
  -e POSTGRES_DB=technexus -e POSTGRES_USER=technexus -e POSTGRES_PASSWORD=technexus \
  postgres:17
```

Then:

```
export NEXUS_API_KEY=... TBA_API_KEY=...
export DB_URL=localhost:5432/technexus DB_USER=technexus DB_PASSWORD=technexus
./gradlew :server:run

curl http://localhost:6867/events
curl http://localhost:6867/event/demo1815
```

Tables are created on startup, so a fresh database needs no setup.

The Gradle daemon forks `:server:run` with the *daemon's* environment, not your shell's — if you export after the daemon
has started, run `./gradlew --stop` first.

Demo events authenticate like any other event: a real `NEXUS_API_KEY` is required even for `demo1815`. Demo events are
created on frc.nexus and are always named `demo` followed by a number.

### Clients

- **Android** — `./gradlew :androidApp:installDebug`, or open the repo in IntelliJ IDEA / Android Studio.
- **iOS** — open `iosApp/TechNexus.xcodeproj` in Xcode and run. Gradle builds the shared framework as part of the Xcode
  build; you do not invoke it yourself. Simulator builds need no Apple Developer account.

## Server routes

| Route                                | Source                                     | Cache  |
|--------------------------------------|--------------------------------------------|--------|
| `GET /events`                        | frc.nexus, all current and upcoming events | 5 min  |
| `GET /event/{event}`                 | frc.nexus, live event and match status     | 15 s   |
| `GET /event/{event}/map`             | frc.nexus, pit map geometry                | 15 min |
| `GET /event/{event}/pits`            | frc.nexus, team number to pit address      | 15 min |
| `GET /event/{event}/teams`           | frc.nexus, teams attending                 | 15 min |
| `GET /event/{event}/match/{matchId}` | The Blue Alliance, reduced to a score      | 1 h    |
| `/batteries/*`                       | Postgres                                   | none   |
| `/cycles/*`                          | Postgres                                   | none   |

`/event/{event}` injects playoff alliance seeds into each match, joined from Nexus's separate alliances endpoint.
Clients never see the raw alliance array.

The three pit routes cache far longer than the schedule because none of them is polled and none is covered by the Nexus
webhook — a pit map is drawn before an event and edited rarely, so the TTL is the whole freshness strategy. They form a
fallback ladder in the client: map, then addresses, then the team list. `/map` answers **204** when an event has no map
drawn, which is the common case; 404 is reserved for a route or event that genuinely doesn't exist, and a 204 caches for
30 seconds rather than 15 minutes so a map drawn on the morning of an event shows up promptly.

## Deployment

The server runs on **Cloud Run** (`technexus-server`, project `technexus-84e3f`, region `us-east1`), behind a
**Cloudflare Worker** at `nexus.jerryxf.net`, with **Postgres on Neon** in AWS `us-east-1`.

Merging to `main` deploys. `build-server.yml` builds the fat jar on every push; on `main` it also builds the image,
pushes it to Artifact Registry, deploys a revision, and smoke-tests `/events`.

Environment variables and secret bindings live on the Cloud Run service, not in CI — the deploy step passes the image
only, so config survives untouched.

To deploy by hand:

```
./gradlew :server:buildFatJar
IMAGE=us-east1-docker.pkg.dev/technexus-84e3f/technexus-server/server:$(date +%m%d-%H%M)
docker buildx build --platform linux/amd64 -t $IMAGE --push .
gcloud run deploy technexus-server --image $IMAGE --region us-east1
```

`--platform linux/amd64` is required from an Apple Silicon Mac; Cloud Run rejects arm64 images with an error about
manifest types that does not mention architecture.

The Worker lives in its own repo. It rewrites the request hostname to the `run.app` origin — Cloud Run routes by `Host`
and 404s anything else — and sets `cf: { cacheEverything: true }` so edge caching honours the `Cache-Control` values
these routes already send.
