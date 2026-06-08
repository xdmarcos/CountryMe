//
//  LocationAuthorizationTests.swift
//  CountryMeTests
//
//  Created by xdmGzDev on 08/06/2026.
//

import Testing
import CoreLocation
@testable import CountryMe

/// Exercises `locationStartAction(for:)` — the pure mapping that decides what
/// `LocationManager.start()` does for each CoreLocation authorization status.
///
/// These run without any `CLLocationManager` instance (it has no mockable seam), since the
/// branching was deliberately extracted into a free function precisely so it could be
/// unit-tested directly.
struct LocationStartActionTests {
    @Test func notDeterminedRequestsAuthorization() {
        #expect(locationStartAction(for: .notDetermined) == .requestAuthorization)
    }

    @Test func authorizedWhenInUseRequestsUpgradeAndMonitors() {
        #expect(locationStartAction(for: .authorizedWhenInUse) == .requestUpgradeAndMonitor)
    }

    @Test func authorizedAlwaysEnablesBackgroundUpdatesAndMonitors() {
        #expect(locationStartAction(for: .authorizedAlways) == .enableBackgroundUpdatesAndMonitor)
    }

    @Test("denied and restricted do nothing in-process", arguments: [
        CLAuthorizationStatus.denied, .restricted
    ])
    func deniedOrRestrictedDoesNothing(status: CLAuthorizationStatus) {
        #expect(locationStartAction(for: status) == .doNothing)
    }

    /// Regression guard for the crash this mapping was extracted to prevent:
    /// `allowsBackgroundLocationUpdates` may ONLY be set to `true` once "Always" authorization
    /// is already granted. Setting it any earlier crashes the app synchronously with an
    /// `NSInternalInconsistencyException` — before `requestAlwaysAuthorization()` ever gets a
    /// chance to show its system prompt, which made the in-app "allow access" button appear to
    /// do nothing. `enableBackgroundUpdatesAndMonitor` must be reachable from `.authorizedAlways`
    /// alone.
    @Test("only .authorizedAlways triggers enabling background updates", arguments: [
        CLAuthorizationStatus.notDetermined, .authorizedWhenInUse, .denied, .restricted
    ])
    func onlyAuthorizedAlwaysEnablesBackgroundUpdates(status: CLAuthorizationStatus) {
        #expect(locationStartAction(for: status) != .enableBackgroundUpdatesAndMonitor)
    }
}

/// Exercises `authorizationGuidance(for:)` — the pure mapping that decides how
/// `ContentView`'s permission banner guides the user for each authorization status.
///
/// Extracted into a free function so this decision is testable without instantiating or
/// rendering the SwiftUI view hierarchy.
struct AuthorizationGuidanceTests {
    @Test func authorizedAlwaysNeedsNoGuidance() {
        #expect(authorizationGuidance(for: .authorizedAlways) == .none)
    }

    @Test func notDeterminedPromptsInApp() {
        #expect(authorizationGuidance(for: .notDetermined) == .promptInApp)
    }

    /// Regression guard: from `.authorizedWhenInUse` (and `.denied`/`.restricted`), iOS either
    /// shows its when-in-use → always upgrade dialog at most once per install, or never shows
    /// one at all — re-prompting via `LocationManager.start()` is then a silent no-op and the
    /// "Allow Location Access Always" button looks broken. Settings is the only reliable path
    /// to "Always" from any of these statuses.
    @Test("authorizedWhenInUse, denied, and restricted all route to Settings", arguments: [
        CLAuthorizationStatus.authorizedWhenInUse, .denied, .restricted
    ])
    func nonPromptableStatusesOpenSettings(status: CLAuthorizationStatus) {
        #expect(authorizationGuidance(for: status) == .openSettings)
    }

    /// Regression guard for the inverse: the in-app prompt button must only ever be offered
    /// from `.notDetermined` — showing it from any other status would (per the above) be a
    /// dead end.
    @Test("only .notDetermined prompts in-app", arguments: [
        CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways, .denied, .restricted
    ])
    func onlyNotDeterminedPromptsInApp(status: CLAuthorizationStatus) {
        #expect(authorizationGuidance(for: status) != .promptInApp)
    }
}
