# CountryMe — Architecture & Key Processes

This doc explains how CountryMe's core flow works (location → country → persisted stat → widget)
and gives a from-scratch primer on how iOS widgets (WidgetKit) work, since that's the part most
likely to be unfamiliar to developers new to the platform.

## 1. The core flow, end to end

```
CLLocationManager (significant-change monitoring)
        │  didUpdateLocations
        ▼
CLGeocoder.reverseGeocodeLocation  →  ISO country code + name
        │
        ▼
recordDetection(...)  →  inserts/updates a CountryStay  →  ModelContext.save()
        │                                                          │
        │                                                  (CloudKit sync, automatic)
        ▼
WidgetCenter.shared.reloadAllTimelines()
        │
        ▼
Widget's TimelineProvider re-fetches CountryStay and redraws
```

### 1.1 Location detection — `LocationManager.swift`

- Uses `startMonitoringSignificantLocationChanges()`, **not** continuous GPS updates. This is a
  deliberate choice: it only fires on ~500m+ movement or cell-tower handoffs, which is plenty of
  resolution for "which country am I in" while sipping battery — and critically, it keeps
  delivering updates while the app is suspended or not running, as long as the user granted
  **"Always"** authorization. Continuous updates would drain the battery for no extra benefit here.
- `CLLocationManagerDelegate` callbacks (`didUpdateLocations`, `didChangeAuthorization`,
  `didFailWithError`) can arrive on a background thread, so they're declared `nonisolated` and
  immediately hop to `@MainActor` via `Task { @MainActor in ... }` before touching any of the
  manager's state or the model context.
- On a location update, it reverse-geocodes via `CLGeocoder` to get `placemark.isoCountryCode`
  (e.g. `"ES"`) and `placemark.country` (e.g. `"Spain"`), then calls `recordDetection`.
- It's iOS-only (`startMonitoringSignificantLocationChanges` doesn't exist on macOS/visionOS), so
  the whole tracking implementation is wrapped in `#if os(iOS)`. Other platforms get a stub that
  reports `.notDetermined` and does nothing — per "start simple", active tracking elsewhere can
  come later.

### 1.2 Aggregation — `CountryStay.swift` / `recordDetection`

`recordDetection` is a free function (not a method on `LocationManager`) specifically so it can be
unit-tested with an in-memory `ModelContext`, with no CoreLocation involvement:

- Look up the existing `CountryStay` for that `countryCode` (uniqueness is enforced *in code*,
  not via `@Attribute(.unique)` — see §3).
- If the new detection is on a **different calendar day** than `lastSeen`, increment `dayCount`.
  Repeated detections on the same day update `lastSeen` but don't inflate the count — this is what
  makes "days spent" meaningful rather than "number of pings received".
- If no record exists yet, insert a new one with `dayCount = 1`.

### 1.3 Persistence + sync — `SharedModelContainer.swift`

A single `ModelContainer` is built once and reused by **both** the app and the widget extension
(see §4 for why that matters). It's configured with:

```swift
ModelConfiguration(
    schema: Schema([CountryStay.self]),
    groupContainer: .identifier("group.gz.xdmdev.CountryMe"),       // App Group
    cloudKitDatabase: .private("iCloud.gz.xdmdev.CountryMe"))       // CloudKit private DB
```

- **App Group container**: puts the SQLite store in shared-app-group storage instead of each
  target's private sandbox, so the app process and the widget process — which are two separate
  executables on disk — read and write the *same* database file.
- **CloudKit private database**: SwiftData mirrors writes to the user's private CloudKit database
  automatically. Sync across the user's devices is "free" — there's no custom networking code;
  `ModelContext.save()` is all it takes. CloudKit's dev schema is created on first sync.

### 1.4 Refreshing the widget

After a successful `recordDetection` + `save()`, `LocationManager` calls
`WidgetCenter.shared.reloadAllTimelines()`. This tells the system "the data widgets read has
changed — re-run the timeline providers now" rather than waiting for the next scheduled refresh
(see §2.4). The widget then re-fetches from the same shared container and redraws.

### 1.5 UI — `ContentView.swift`

Plain SwiftUI + `@Query`:
- `@Query(sort: \CountryStay.dayCount, order: .reverse)` gets all stays sorted by day count.
- "Current country" = the stay with the most recent `lastSeen` (computed locally — `@Query` can
  only express one sort).
- "Most visited" = `stays.prefix(3)`.
- `NavigationViewWrapper` branches on `#if os(macOS)` to pick `NavigationSplitView` vs. a flat
  view — the established pattern for platform differences here; extend it rather than introducing
  a new navigation abstraction if more platform-specific UI is needed.

---

## 2. How iOS widgets work (WidgetKit primer)

If you haven't built a widget before, the mental model is quite different from a normal view:
**a widget doesn't run continuously and it can't "just" read live app state.** Apple's system
process (`SpringBoard`/the widget host) decides when to render your widget, and it does so by
asking *your* code, running in a separate, short-lived extension process, to hand over a
description of what to show — not by keeping your UI alive on screen.

### 2.1 The extension is a separate mini-app

A Widget Extension is its own target (`CountryMeWidgetExtension` here), with its own bundle ID
(`gz.xdmdev.CountryMe.CountryMeWidget`), its own `Info.plist`
(`NSExtensionPointIdentifier = com.apple.widgetkit-extension`), and its own process at runtime. It
gets embedded inside the host app's `.app/PlugIns/` folder and is launched independently by the
system — usually briefly, to compute a timeline, then suspended again. It does **not** share memory,
`UserDefaults`, in-process singletons, or `ModelContainer` instances with the main app. Anything
they need to share has to go through a mechanism the OS explicitly provides for cross-process
sharing — here, an **App Group container** (§4) holding the SwiftData/CloudKit store.

### 2.2 `WidgetBundle` — the entry point

```swift
@main
struct CountryMeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountryMeWidget()
    }
}
```

Analogous to `@main App` for a normal app — it's the extension's entry point, and a single bundle
can host multiple distinct widgets (a counter widget, a calendar widget, etc., each its own
`Widget`). The Xcode template generates a `WidgetBundle` with example `Widget`, `ControlWidget`,
and `ActivityKit` Live Activity members; we deleted the latter two and the example
`ConfigurationAppIntent` to keep things "start simple" — they're entirely different extension
points (Control Center controls, Lock Screen/Dynamic Island activities) that this app doesn't use.

### 2.3 `Widget` — describes one widget kind

```swift
struct CountryMeWidget: Widget {
    let kind: String = "CountryMeWidget"          // stable identity across launches/updates

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CountryMeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)   // required since iOS 17
        }
        .configurationDisplayName("CountryMe")
        .description("Shows your current country and most visited countries.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

- `kind` is a stable string identity for this widget — used by the system to track which widgets
  the user has placed and to route reload requests.
- `StaticConfiguration` is the simplest `WidgetConfiguration`: no user-facing settings. The
  alternative, `AppIntentConfiguration` (what the Xcode template generates by default), lets the
  user customize the widget via an `AppIntent` — e.g. "pick which city to show". We don't need
  that here, so a plain `StaticConfiguration` keeps things simpler; this can be upgraded later if,
  say, you want the user to choose which country's stats to pin.
- `containerBackground(_:for:)` is mandatory on modern iOS — widgets render their own background
  (which the system can tint/recolor depending on context — Lock Screen, StandBy, etc.), so views
  must not paint an opaque background themselves.
- `supportedFamilies` declares which sizes this widget can render at; the user picks a size when
  adding it to the Home Screen. We support `.systemSmall` and `.systemMedium`.

### 2.4 `TimelineProvider` — the heart of a widget

This is the piece that's genuinely new if you've only built normal apps. A widget doesn't get to
say "redraw me whenever my data changes" the way a SwiftUI view does — instead, it pre-computes a
**timeline**: an array of `(date, content)` pairs, handed to the system in advance, which the
system then displays at the appropriate times *without* re-invoking your code.

```swift
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CountryMeEntry { ... }
    func getSnapshot(in context: Context, completion: @escaping (CountryMeEntry) -> Void) { ... }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CountryMeEntry>) -> Void) { ... }
}
```

- **`placeholder`** — a fast, synchronous, content-free skeleton shown while the real data loads
  (e.g. in the widget gallery, or the very first render). Must not block or do I/O.
- **`getSnapshot`** — a single representative entry, used for quick previews (e.g. when the user
  is browsing the widget gallery, or for transient contexts). Should be fast; can use real data if
  cheap to fetch.
- **`getTimeline`** — the real deal: returns a `Timeline<Entry>`, which is an array of entries plus
  a **reload policy**:
  - `.atEnd` — ask again once the last entry's date passes.
  - `.after(date)` — ask again at a specific future date.
  - `.never` — only reload when explicitly told to (via `WidgetCenter.reloadTimelines`).

  We use a single entry with `.after(now + 15 minutes)`. Combined with the app calling
  `WidgetCenter.shared.reloadAllTimelines()` immediately after recording a new detection, the
  widget refreshes promptly when there's something new to show, and otherwise at most every 15
  minutes (the system also imposes its own daily refresh budget per widget — you cannot force
  high-frequency polling).
- **`TimelineEntry`** — a plain `Sendable`-ish value type with at minimum a `date: Date`; here,
  `CountryMeEntry` also carries the `current` country and `topStays` snapshot needed to render.
  Entries are computed *once* per timeline request and then displayed verbatim at their scheduled
  times — there's no "live" data binding inside a placed widget.

Because `getSnapshot`/`getTimeline` are completion-handler-based (not `async`) in the
`TimelineProvider` protocol (as opposed to the newer `AppIntentTimelineProvider`, which is
`async`), our `makeEntry()` helper does its `ModelContext` fetch synchronously and returns
immediately — appropriate here since SwiftData's local fetch is fast and we're not making a network
call to build the entry.

### 2.5 The entry view — pure rendering, no state

```swift
struct CountryMeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CountryMeEntry
    var body: some View { ... }
}
```

- `@Environment(\.widgetFamily)` tells the view which size it's being asked to render at
  (`.systemSmall`, `.systemMedium`, `.systemLarge`, plus Lock Screen/StandBy families on supported
  devices), so a single view type can branch on `family` to produce different layouts — exactly
  like `CountryMeWidgetEntryView` does here (flag+name only for small; + a "Most Visited" list for
  medium).
- The view is handed a fully-formed `entry` and just renders it — no `@State`, no `@Query`, no
  fetching. All the "thinking" happened in the provider; the view's job is to be a deterministic
  function of `(entry, family, environment)`.

### 2.6 `#Preview` for widgets

```swift
#Preview(as: .systemMedium) {
    CountryMeWidget()
} timeline: {
    CountryMeEntry(date: .now, current: nil, topStays: [])
}
```

The `#Preview(as:)` widget-flavored macro renders your `Widget` at a given family using
hand-supplied entries — exactly the kind of thing `getSnapshot`/`getTimeline` would normally
produce — without needing CoreLocation, a real device, or a populated database. This is the
fastest way to iterate on widget layout (Xcode's canvas, or the `RenderPreview` MCP tool used
during development of this feature).

---

## 3. CloudKit-compatible SwiftData modeling

`CountryStay` follows rules required for a SwiftData model that syncs through CloudKit's private
database (these are CloudKit schema constraints, not SwiftData ones — violating them surfaces as
runtime container-creation failures, not compile errors):

- **No `@Attribute(.unique)`** — CloudKit's schema has no concept of unique constraints.
  Uniqueness-by-`countryCode` is instead enforced in application code, inside `recordDetection`
  (fetch-then-update-or-insert).
- **Every stored property has a default value** (`= ""`, `= 0`, `= .distantPast`, …) — CloudKit
  records are schemaless/optional by nature, and SwiftData needs a way to materialize a value for
  fields that may be absent on an older record version.
- **No required (non-optional, non-defaulted) relationships** — same root cause; CloudKit can't
  guarantee referential integrity the way a local SQL store can. (`CountryStay` has no
  relationships at all, so this is moot today, but keep it in mind if the model grows — e.g. if you
  add a `Visit` entity linked to a `CountryStay`.)

---

## 4. Sharing data between the app and the widget extension

Two processes (app + widget extension) need to see *one* database. Two pieces make that possible:

1. **App Group** (`group.gz.xdmdev.CountryMe`) — a capability that creates a shared container
   directory both targets' sandboxes can read/write. `SharedModelContainer` points its
   `ModelConfiguration` at `.groupContainer(.identifier(...))`, so the SQLite store physically
   lives there instead of in either target's private `Application Support`.
2. **Same `ModelContainer` schema/config in both processes** — `SharedModelContainer.shared` is a
   single `enum` with a `static let shared: ModelContainer`, used by `CountryMeApp` (via
   `.modelContainer(SharedModelContainer.shared)`) *and* by the widget's `Provider`
   (`ModelContext(SharedModelContainer.shared)`). Same schema, same App Group identifier, same
   CloudKit container — so both processes open the exact same store consistently.

Both targets' entitlements must declare **matching** values for the App Group and the iCloud
container — registered through Xcode's Signing & Capabilities UI (not just written into the
entitlements XML), because the *provisioning profile* needs to include them too, or codesigning /
sandbox access silently fails at runtime.

### 4.1 Cross-target file membership with synchronized groups

This project uses Xcode's newer **file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`, Xcode 16+/objectVersion 77): each target's source folder
(`CountryMe/`, `CountryMeWidget/`, …) is synced automatically — drop a `.swift` file in the folder
and it's compiled into that folder's target, no manual "add to target" step, no `.pbxproj` churn
for routine additions.

The wrinkle: `CountryStay.swift`, `SharedModelContainer.swift`, and `CountryFlag.swift` physically
live in `CountryMe/` (the app target's folder) but the widget extension also needs to compile
them. With synchronized groups, **cross-target membership for individual files is set per-file**,
via Xcode's File Inspector (⌥⌘1 → "Target Membership" → check the extra target) — not by editing
the `.pbxproj` `fileSystemSynchronizedGroups` arrays (those map a *folder* to its *home* target,
not individual extra memberships). Once checked, Xcode records a membership exception for that
file/target pair under the hood, and it compiles into both targets going forward.

If you add more files that the widget needs (e.g. a future shared formatting helper), do the same:
select it → File Inspector → tick `CountryMeWidgetExtension`.

---

## 5. Where to look when extending this

| Want to… | Look at |
|---|---|
| Change how/when country detection happens | `LocationManager.swift` (`start()`, `handle(_:)`) |
| Change the "days visited" rule | `recordDetection` in `CountryStay.swift` (and its tests in `CountryMeTests.swift`) |
| Add fields to the persisted model | `CountryStay.swift` — remember the CloudKit rules in §3, and bump `Schema` if you add a new `@Model` type |
| Change the shared store's location/sync target | `SharedModelContainer.swift` |
| Change widget layout/sizes/refresh cadence | `CountryMeWidget/CountryMeWidget.swift` (`Provider`, `CountryMeWidgetEntryView`, `supportedFamilies`, the `.after(...)` policy) |
| Add a file the widget needs to compile | put it in `CountryMe/`, then set its Target Membership to include `CountryMeWidgetExtension` (§4.1) |
| Change main UI | `ContentView.swift` (extend `NavigationViewWrapper` for platform-specific layout, don't replace it) |
