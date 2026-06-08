# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

CountryMe — "Counter for spent days by country". A SwiftUI + SwiftData app, currently scaffolded from
Xcode's default template (the `Item` model and list UI in `ContentView` are template placeholders, not
the final feature).

- Bundle ID: `gz.xdmdev.CountryMe`
- Swift 5.0, deployment target 26.5 (iOS / macOS / visionOS — see `SUPPORTED_PLATFORMS` in the project)
- Single Xcode project `CountryMe.xcodeproj` with three targets: `CountryMe`, `CountryMeTests`, `CountryMeUITests`
- One scheme: `CountryMe`

## Commands

Build and test via `xcodebuild` (run from the directory containing `CountryMe.xcodeproj`):

```sh
# Build for iOS Simulator
xcodebuild -project CountryMe.xcodeproj -scheme CountryMe -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run all tests (unit + UI)
xcodebuild -project CountryMe.xcodeproj -scheme CountryMe -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single test (Swift Testing target)
xcodebuild -project CountryMe.xcodeproj -scheme CountryMe -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CountryMeTests/CountryMeTests/example test

# Run a single UI test (XCTest target)
xcodebuild -project CountryMe.xcodeproj -scheme CountryMe -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CountryMeUITests/CountryMeUITests/testExample test
```

Adjust `-destination` to target macOS (`platform=macOS`) or visionOS (`platform=visionOS Simulator,name=Apple Vision Pro`)
as needed — the app is multiplatform (`TARGETED_DEVICE_FAMILY = "1,2,7"`: iPhone, iPad, Vision).

Opening the project in Xcode (`open CountryMe.xcodeproj`) and using ⌘B / ⌘U is equivalent and often faster
for iterative work.

## Architecture

- **Persistence**: SwiftData. `CountryMeApp` builds a single `ModelContainer` (schema currently just `Item`)
  and injects it via `.modelContainer(...)`. Views read/write through `@Environment(\.modelContext)` and
  `@Query`, following standard SwiftData/SwiftUI conventions — there is no separate data-access layer.
- **Entry point**: `CountryMeApp.swift` — `@main` App struct, owns the `ModelContainer`, hosts `ContentView`
  in a `WindowGroup`.
- **UI**: `ContentView.swift` contains a `fileprivate` `NavigationViewWrapper` that branches on `#if os(macOS)`
  to choose between `NavigationSplitView` (macOS) and a plain content view (iOS/visionOS). This is the
  established pattern for handling platform differences in the UI layer — extend it rather than introducing
  a different navigation abstraction.
- **Tests**: `CountryMeTests` uses the new Swift Testing framework (`import Testing`, `@Test`, `#expect`);
  `CountryMeUITests` uses XCTest/XCUIApplication for UI and launch-performance tests.
- **Capabilities**: `CountryMe.entitlements` enables CloudKit (`com.apple.developer.icloud-services`) and
  push notifications (`aps-environment`), and `Info.plist` declares the `remote-notification` background
  mode — CloudKit sync and remote notifications are intended capabilities even though no sync code exists yet.

## Notes

- `Item` (timestamp-only model) and the list UI in `ContentView` are leftover Xcode template code for the
  "counter for spent days by country" feature — expect to replace/extend the SwiftData schema and views as
  the real domain model (countries, stays, dates) is built out.
