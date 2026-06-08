//
//  LocationManager.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import Combine
import CoreLocation
import SwiftData
import WidgetKit

/// What `LocationManager.start()` should do for a given CoreLocation authorization status.
///
/// Extracted into a pure function (`locationStartAction(for:)`) so this branching — including
/// the crash-prevention rule that `enableBackgroundUpdatesAndMonitor` is reachable *only* from
/// `.authorizedAlways` — is unit-testable without a real, unmockable `CLLocationManager`.
enum LocationStartAction: Equatable {
    /// `.notDetermined` — the only status from which the in-app system permission prompt
    /// can still appear.
    case requestAuthorization
    /// `.authorizedWhenInUse` — ask for the upgrade to "Always" (iOS shows that dialog at
    /// most once per install) and start monitoring in the meantime so tracking isn't idle
    /// while the user decides.
    case requestUpgradeAndMonitor
    /// `.authorizedAlways` — the *only* status from which `allowsBackgroundLocationUpdates`
    /// may be set to `true`; setting it any earlier crashes the app synchronously with an
    /// `NSInternalInconsistencyException`, before any permission prompt can appear.
    case enableBackgroundUpdatesAndMonitor
    /// `.denied` / `.restricted` (and any future unknown case) — nothing achievable
    /// in-process; the user has to go through Settings.
    case doNothing
}

func locationStartAction(for status: CLAuthorizationStatus) -> LocationStartAction {
    switch status {
    case .notDetermined:
        return .requestAuthorization
    case .authorizedWhenInUse:
        return .requestUpgradeAndMonitor
    case .authorizedAlways:
        return .enableBackgroundUpdatesAndMonitor
    case .denied, .restricted:
        return .doNothing
    @unknown default:
        return .doNothing
    }
}

/// Watches for significant location changes, reverse-geocodes them to a country, and records
/// the detection into the shared SwiftData store.
///
/// Significant-change monitoring (rather than continuous updates) is deliberately coarse — it
/// fires on movements of roughly 500m+ or cell-tower handoffs, which is plenty of resolution
/// for "which country am I in" while being far gentler on battery, and it keeps working while
/// the app is suspended/closed (with "Always" authorization). It's an iOS-only API, so the
/// whole tracking implementation is guarded by `#if os(iOS)`; other platforms compile with a
/// stub that reports `.notDetermined` and does nothing — per "start simple", active tracking on
/// macOS/visionOS can come later.
// Note: `objectWillChange` is declared explicitly (instead of relying on `@Published` to
// synthesize it) and the published values use plain `willSet` hooks. Under this target's
// `default-isolation=MainActor`, an `NSObject` subclass with `@Published` properties fails to
// synthesize the `ObservableObject` conformance ("does not conform to protocol
// 'ObservableObject'") — Combine's property-wrapper synthesis doesn't play well with `@objc`
// dynamism plus global-actor isolation. Manual `objectWillChange.send()` sidesteps it.
final class LocationManager: NSObject, ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var authorizationStatus: CLAuthorizationStatus {
        willSet { objectWillChange.send() }
    }
    private(set) var lastError: String? {
        willSet { objectWillChange.send() }
    }

    #if os(iOS)
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    #endif
    private let modelContainer: ModelContainer

    // `modelContainer` defaults inside the body rather than via a default-argument expression:
    // default-argument expressions aren't evaluated in the function's isolation context, so
    // referencing the main-actor-isolated `SharedModelContainer.shared` there is rejected.
    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer ?? SharedModelContainer.shared
        #if os(iOS)
        self.authorizationStatus = manager.authorizationStatus
        #else
        self.authorizationStatus = .notDetermined
        #endif
        super.init()
        #if os(iOS)
        manager.delegate = self
        #endif
    }

    /// Requests "Always" permission (so monitoring survives the app being closed) and, once
    /// granted, starts significant-change monitoring. Safe to call repeatedly — e.g. on every
    /// launch — it's a no-op once already authorized and monitoring.
    func start() {
        #if os(iOS)
        switch locationStartAction(for: manager.authorizationStatus) {
        case .requestAuthorization:
            manager.requestAlwaysAuthorization()
        case .requestUpgradeAndMonitor:
            manager.requestAlwaysAuthorization()
            manager.startMonitoringSignificantLocationChanges()
        case .enableBackgroundUpdatesAndMonitor:
            manager.allowsBackgroundLocationUpdates = true
            manager.startMonitoringSignificantLocationChanges()
        case .doNothing:
            break
        }
        #endif
    }

    #if os(iOS)
    private func handle(_ location: CLLocation) {
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first, let code = placemark.isoCountryCode else {
                    return
                }
                let name = placemark.country ?? code

                let context = ModelContext(modelContainer)
                try recordDetection(countryCode: code, countryName: name, date: location.timestamp, in: context)
                try context.save()

                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
    #endif
}

#if os(iOS)
extension LocationManager: CLLocationManagerDelegate {
    // CLLocationManagerDelegate callbacks can arrive on a background queue, so these are
    // `nonisolated` and hop back to the main actor before touching `self`'s state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedAlways {
                // Only safe to set once "Always" is actually granted (see `start()`) — this
                // catches the case where the user upgrades permission via Settings while the
                // app is already running, so we don't have to wait for the next `start()`.
                manager.allowsBackgroundLocationUpdates = true
                manager.startMonitoringSignificantLocationChanges()
            } else if status == .authorizedWhenInUse {
                manager.startMonitoringSignificantLocationChanges()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        Task { @MainActor in
            handle(newest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            lastError = message
        }
    }
}
#endif
