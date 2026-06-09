//
//  LocationManager.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import Observation
import CoreLocation
import MapKit
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
@Observable
final class LocationManager: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastError: String?

    /// What `CLLocationManagerDelegate` reports, funneled through a single `AsyncStream` so one
    /// `for await` loop can apply every update on the main actor — replacing a `Task { @MainActor
    /// in … }` hop per callback with one long-running consumer.
    private enum LocationEvent {
        case authorization(CLAuthorizationStatus)
        case location(CLLocation)
        case failure(String)
    }

    #if os(iOS)
    private let manager = CLLocationManager()
    private let events: AsyncStream<LocationEvent>
    private let continuation: AsyncStream<LocationEvent>.Continuation
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    #endif
    private let modelContainer: ModelContainer

    // `modelContainer` defaults inside the body rather than via a default-argument expression:
    // default-argument expressions aren't evaluated in the function's isolation context, so
    // referencing the main-actor-isolated `SharedModelContainer.shared` there is rejected.
    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer ?? SharedModelContainer.shared
        #if os(iOS)
        self.authorizationStatus = manager.authorizationStatus
        let (events, continuation) = AsyncStream.makeStream(of: LocationEvent.self)
        self.events = events
        self.continuation = continuation
        #else
        self.authorizationStatus = .notDetermined
        #endif
        super.init()
        #if os(iOS)
        manager.delegate = self
        startConsuming()
        #endif
    }

    #if os(iOS)
    deinit {
        continuation.finish()
        consumerTask?.cancel()
    }
    #endif

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

    /// Fills in any calendar days that elapsed since the last recorded detection without a
    /// significant-location-change event — i.e. the user stayed in the same country overnight.
    ///
    /// Called every time the app comes to the foreground (via the App's `scenePhase` observer)
    /// so a stationary user always sees an up-to-date day count without waiting for a location
    /// event that may never arrive.
    func checkDayRollover() {
        let context = ModelContext(modelContainer)
        do {
            try fillMissingDays(in: context)
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = error.localizedDescription
        }
    }

    #if os(iOS)
    /// The single consumer of `events` — applies every authorization change, location, and
    /// error on the main actor, in arrival order. Replaces the old per-callback `Task { @MainActor
    /// in … }` spawns with one long-running loop that exits when `continuation.finish()` runs
    /// (in `deinit`) or the task is cancelled.
    private func startConsuming() {
        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.events {
                switch event {
                case .authorization(let status):
                    self.authorizationStatus = status
                    self.applyAuthorization(status)
                case .location(let location):
                    await self.handle(location)
                case .failure(let message):
                    self.lastError = message
                }
            }
        }
    }

    /// Reacts to an authorization change that happens while the app is already running — e.g.
    /// the user upgrades permission via Settings — without waiting for the next `start()`.
    /// Mirrors the rules in `locationStartAction(for:)`: `allowsBackgroundLocationUpdates` is
    /// only safe to set under `.authorizedAlways`.
    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            manager.allowsBackgroundLocationUpdates = true
            manager.startMonitoringSignificantLocationChanges()
        case .authorizedWhenInUse:
            manager.startMonitoringSignificantLocationChanges()
        default:
            break
        }
    }

    private func handle(_ location: CLLocation) async {
        do {
            // `CLGeocoder.reverseGeocodeLocation` is deprecated in favor of MapKit's reverse
            // geocoding request. `region` is a `Locale.Region` whose `identifier` is the ISO
            // 3166-1 alpha-2 code (e.g. "ES") — the MapKit equivalent of `CLPlacemark.isoCountryCode`.
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            let mapItems = try await request.mapItems
            guard let representations = mapItems.first?.addressRepresentations,
                  let region = representations.region else {
                return
            }
            let code = region.identifier
            let name = representations.regionName ?? code

            let context = ModelContext(modelContainer)
            try recordDetection(
                countryCode: code,
                countryName: name,
                coordinate: location.coordinate,
                date: location.timestamp,
                in: context
            )
            try context.save()

            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = error.localizedDescription
        }
    }
    #endif
}

#if os(iOS)
extension LocationManager: CLLocationManagerDelegate {
    // CLLocationManagerDelegate callbacks can arrive on a background queue, so these are
    // `nonisolated` — they only touch the `Sendable` `continuation`, never observable state,
    // and simply yield events for `startConsuming()`'s main-actor loop to apply in order.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield(.authorization(manager.authorizationStatus))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        continuation.yield(.location(newest))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation.yield(.failure(error.localizedDescription))
    }
}
#endif
