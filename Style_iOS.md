# TechNexus iOS style guide

Conventions for the SwiftUI layer. Android follows its own Material conventions; this document does not apply there.

---

## Deployment target

**The floor is iOS 16.0.** Live Activities need 16.1 and are gated by ActivityKit itself; everything else in the app
runs on 16.

The floor rises by accident, not by decision, because SwiftUI added shorthand spellings of old types in later releases
and the compiler accepts them without comment:

| Shorthand                    | Available | Same thing as                           | Available |
|------------------------------|-----------|-----------------------------------------|-----------|
| `.rect(cornerRadius:style:)` | iOS 17    | `RoundedRectangle(cornerRadius:style:)` | iOS 13    |
| `.rect`                      | iOS 17    | `Rectangle()`                           | iOS 13    |
| `.circle`                    | iOS 17    | `Circle()`                              | iOS 13    |
| `.capsule`                   | iOS 17    | `Capsule()`                             | iOS 13    |

These produce identical views. Reaching for the shorthand in a `clipShape`, `contentShape`, or `fill` silently makes the
file iOS 17-only, and nothing surfaces until someone pins the deployment target and the build breaks. **Use the
initializer form.** One `.clipShape(.rect(...))` in `SettingsCard` was the only thing standing between this app and its
stated iOS 16 support.

Genuinely newer APIs are fine behind `if #available`. Note that the check widens the availability context for everything
inside it — `.rect` inside an `if #available(iOS 26.0, *)` block compiles against a 16.0 target, because that branch can
only run on 26.

Pin `IPHONEOS_DEPLOYMENT_TARGET` explicitly on all six build configurations. `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)`
tracks whatever Xcode is installed and moves on its own.

---

## Typography

### The rule

**Use semantic fonts.** They scale with the user's Dynamic Type setting; fixed point sizes do not. Someone who has
turned text size up gets nothing from
`.system(size: 9)`.

```swift
Text("Qualification 15").font(.headline)          // scales
Text("Qualification 15").font(.system(size: 17))  // frozen
```

Fixed sizes are allowed in exactly one place: **inside the Dynamic Island.**
Its regions have hard pixel budgets, it barely honours Dynamic Type anyway, and overflow there would be a visual bug.
Everywhere else — the app, and the Lock Screen Live Activity card — uses semantic fonts.

When you do use a fixed size, leave a comment saying why.

### Replacing what's already there

Default point sizes at the Large (standard) setting:

| Semantic       | pt | Weight   |
|----------------|----|----------|
| `.largeTitle`  | 34 | regular  |
| `.title`       | 28 | regular  |
| `.title2`      | 22 | regular  |
| `.title3`      | 20 | regular  |
| `.headline`    | 17 | semibold |
| `.body`        | 17 | regular  |
| `.callout`     | 16 | regular  |
| `.subheadline` | 15 | regular  |
| `.footnote`    | 13 | regular  |
| `.caption`     | 12 | regular  |
| `.caption2`    | 11 | regular  |

Migration for the sizes currently in the codebase:

| Currently             | Use                                              |
|-----------------------|--------------------------------------------------|
| `size: 36`            | `.largeTitle`                                    |
| `size: 24, .bold`     | `.title2` + `.bold()`                            |
| `size: 15, .semibold` | `.subheadline` + `.weight(.semibold)`            |
| `size: 14`            | `.subheadline`                                   |
| `size: 13`            | `.footnote`                                      |
| `size: 12`            | `.caption`                                       |
| `size: 11`            | `.caption2`                                      |
| `size: 10, 9, 8`      | `.caption2` — or keep fixed, Dynamic Island only |

Apply weight as a modifier rather than baking it into the size:

```swift
Text("3990").font(.caption2).fontWeight(.semibold)
```

Monospaced digits for anything that ticks, so the layout doesn't jitter as numerals change width:

```swift
Text(timerInterval: range, countsDown: true)
    .font(.system(.headline, design: .monospaced))
    .monospacedDigit()
```

### Guarding against overflow

Semantic fonts grow when the user turns text size up. Anywhere space is fixed — Live Activity cards especially — pair
them with:

```swift
.lineLimit(1)
.minimumScaleFactor(0.85)
```

---

## Colour

### Status colours have one source per target

The app reads from `MatchStatusHelper.display(for:isCurrentlyPlaying:)`, which returns label, colour and icon together.
Never re-derive a status colour in a view.

The Live Activity extension has its own copy in `LiveActivityFormat`. This is deliberate, not an oversight: the
extension doesn't link `ComposeApp`, so it can't import `MatchStatusHelper`. The two also take different inputs — the
app maps raw API statuses, the extension maps strings the manager already resolved. **If you change a status colour,
change it in both.**

| Status       | Colour    |
|--------------|-----------|
| On field     | green     |
| Done         | gray      |
| On deck      | blue      |
| Now queuing  | orange    |
| Queuing soon | purple    |
| Unknown      | secondary |

Alliance colours are `.red` and `.blue`, always.

### Everything else is semantic

Use system colours so light and dark mode both work without branching:

| Purpose            | Token                                      |
|--------------------|--------------------------------------------|
| Screen background  | `Color(.systemGroupedBackground)`          |
| Card surface       | `Color(.secondarySystemGroupedBackground)` |
| Primary text       | `.primary`                                 |
| Supporting text    | `.secondary`                               |
| De-emphasised text | `.tertiary`                                |
| Hairlines          | `Color(.systemGray5)`                      |

Never hardcode a hex or an RGB literal for chrome. Hex is only for team highlight colours, which come from user data and
are decoded through
`LiveActivityFormat.color(hex:)`.

---

## Spacing and shape

Stick to the scale already in use — `2, 4, 6, 8, 12, 14, 16, 20`. If a layout seems to need 7 or 15, it usually needs a
different structure.

| Element              | Radius |
|----------------------|--------|
| Settings / list card | 14     |
| Match card           | 12     |
| Live Activity box    | 6      |
| Badge / pill         | 4–6    |

Card padding is 14 horizontal, 12 vertical. Section spacing is 20.

Use `.rect(cornerRadius:style: .continuous)` for anything card-sized; the continuous curve matches the system's own
surfaces.

---

## Motion

Use system curves and let SwiftUI pick the duration:

```swift
.animation(.default, value: hasChanges)   // yes
.easeInOut(duration: 0.3)                 // no, unless you can justify it
```

Drive animation from state changes, not from mutating state inside `.onAppear`. A view that reappears — a tab switch, a
list re-render — fires `onAppear` again with the state already at its target, so the animation silently never restarts.
This has bitten this codebase twice:

```swift
// Restarts correctly
.opacity(isDimmed ? 0.25 : 1.0)
.animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDimmed)
.onAppear { isDimmed = true }
.onDisappear { isDimmed = false }
```

A `repeatForever` animation started from `.onAppear` fires while the view is still being inserted, so it captures the
insertion's geometry change alongside whatever you meant to animate — and then oscillates *both* forever. In a centred
container that shows up as the view drifting sideways in time with the fade. Put the `.frame` outside the `.animation`
so the slot can't resize, and start the animation from `.task` after a short sleep so layout has settled.

Prefer `.task(id:)` over `.onChange(of:)` — one spelling that works on iOS 16 and 17+, instead of an availability branch
that splits view identity.

---

## Stale and offline state

Data that may no longer be current is marked, never silently shown as fact.

- **Icon:** `icloud.slash`, next to the affected content
- **Dimming:** reduce the affected content to `0.6` opacity
- **Never** blank a screen because a refresh failed — keep the last known data and mark it

This applies to the schedule banner, the header, and the Live Activity, which uses `context.isStale` (set five minutes
out by `staleDate` in the manager).

---

## Live Activity

**Card background** is set once, in `LiveActivityFormat.backgroundTint`. It is translucent on purpose so the wallpaper
reads through rather than presenting a hard black slab.

**Region budgets.** Compact leading and trailing are roughly 60pt each — three or four characters. The minimal
presentation holds one glyph. `H:MM:SS` is right at the edge of what compact trailing holds, so it is paired with
`.minimumScaleFactor` rather than being swapped for clock time past an hour out. That swap used to exist and was
removed: `3:45` reads identically as a countdown and as a wall clock, so the mode change made the number ambiguous at
exactly the glance it was meant to serve.

**Never encode meaning in colour alone.** The minimal presentation has room for one symbol and nothing else, so the
symbol varies by status rather than just its tint. Colourblind users get nothing from a green flag versus an orange one.

**The app icon in the corner is the icon asset**, not something the activity can restyle. iOS app icons cannot contain
transparency. A black-on-white icon will always render as a white square on a dark card — the fix is redesigning the
icon, not the Live Activity.

---

## Copy

Sentence case for everything except short all-caps labels (`RED`, `YOUR TEAMS`).

Name things by what the user recognises. "Event ID," not "eventKey."

Say what a control does. "Show on Lock Screen," not "Enable."

Failure states say what happened and what to do:

> Couldn't load 2026daly. Check your connection, or the Event ID in Settings.

Not "An error occurred."

**No placeholder copy ships.** "Coming soon," "Nothing here yet," and "doesn't do anything yet" are App Store rejections
under Guideline 4.2. If a section has nothing in it, remove or comment out the section.
