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
        // Ensures background delivery keeps working consistently across iOS versions/devices —
        // significant-change monitoring is documented to wake the app while suspended/terminated
        // without this, but this flag makes that behavior explicit and reliable rather than
        // relying on undocumented defaults. Requires "Always" authorization plus the `location`
        // background mode (already declared in Info.plist) or it's a no-op.
        manager.allowsBackgroundLocationUpdates = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Ask to upgrade to "Always" so tracking continues in the background; start
            // monitoring in the meantime so we're not idle while the user decides.
            manager.requestAlwaysAuthorization()
            manager.startMonitoringSignificantLocationChanges()
        case .authorizedAlways:
            manager.startMonitoringSignificantLocationChanges()
        case .denied, .restricted:
            break
        @unknown default:
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
            if status == .authorizedAlways || status == .authorizedWhenInUse {
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
