# TechNexus

A companion app for FRC teams: match schedule, queue status, and pit tools, built on live data
from [Nexus](https://frc.nexus).

Kotlin Multiplatform with a native SwiftUI layer on iOS and Compose on Android.

## Modules

Five build units in one repo. They share code but ship independently — nothing coordinates their release.

| Module       | Output                  | Notes                                                                                                                                          |
|--------------|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared`     | iOS framework + JVM jar | Data classes and JSON config. The wire contract: server and clients compile against the same `@Serializable` types, so the format can't drift. |
| `composeApp` | KMP library             | Client logic — API calls, settings storage. Depends on `shared`.                                                                               |
| `androidApp` | `.apk` / `.aab`         | Android UI.                                                                                                                                    |
| `iosApp`     | `.ipa`                  | SwiftUI app and the Live Activity extension. Built by Xcode, not Gradle.                                                                       |
| `server`     | fat jar                 | Ktor service behind `nexus.raphdf201.net`. Depends on `shared`, not on `composeApp`.                                                           |

## Data sources

| Source            | Used for                                                  | Notes                                                                                                                                                                       |
|-------------------|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| frc.nexus         | Event list, live match and queue status, timing estimates | Requires an API key, including for demo events. Only carries current and upcoming events — past seasons are purged, so a hardcoded real event key 404s once the event ends. |
| The Blue Alliance | Match scores                                              | Requires an API key.                                                                                                                                                        |

The clients never call either directly; both go through the server, which holds the keys.

## Notifications

Not built yet. When they are, the transport is **APNs directly on iOS, FCM on Android** — not FCM for both.

Firebase was previously linked on both platforms with no code behind it, which cost an App Store privacy disclosure for
nothing and made `google-services.json`
a build requirement for a file nobody had. It has been removed. Re-add it only for Android, and only when there is
something to wire it to.

Routing iOS through FCM buys nothing: FCM's iOS transport *is* APNs, it needs the same `.p8` auth key, and it has
historically lagged Apple's Live Activity payload format. The server holds the keys for both.

## Shifts

Auto 20s Transition shift 10s Alliance shift, lowest auto score enabled, 25s Alliance shift 25s Alliance shift 25s
Alliance shift 25s Endgame 30s Total 160s / 2min40s

## Server config

All configuration comes from the environment. Every variable is required, and a missing one fails at startup naming all
of them at once.

| Variable        | Purpose                                                     |
|-----------------|-------------------------------------------------------------|
| `NEXUS_API_KEY` | frc.nexus API key, from https://frc.nexus/api               |
| `TBA_API_KEY`   | The Blue Alliance key, for match scores                     |
| `DB_URL`        | Postgres host and database, e.g. `localhost:5432/technexus` |
| `DB_USER`       | Postgres user                                               |
| `DB_PASSWORD`   | Postgres password                                           |

`TECHNEXUS_CACHE_DIR` is optional and moves the outbound HTTP cache off the working directory, which a container often
mounts read-only.

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

Demo events authenticate like any other event — a real `NEXUS_API_KEY` is required even for `demo1815`. Demo events are
created on frc.nexus and are always named `demo` followed by a number.

## Server routes

| Route                                | Source                                     | Cache |
|--------------------------------------|--------------------------------------------|-------|
| `GET /events`                        | frc.nexus, all current and upcoming events | 5 min |
| `GET /event/{event}`                 | frc.nexus, live event and match status     | 15 s  |
| `GET /event/{event}/match/{matchId}` | The Blue Alliance, reduced to a score      | 1 h   |
| `/batteries/*`                       | Postgres                                   | none  |
