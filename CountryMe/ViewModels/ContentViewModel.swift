//
//  ContentViewModel.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import CoreLocation

/// How the "needs Always access" banner should guide the user for a given authorization
/// status.
///
/// Extracted into a pure function (`authorizationGuidance(for:)`) so this decision —
/// including which statuses can still show iOS's own permission prompt versus which can
/// only be resolved through Settings — is unit-testable without rendering SwiftUI.
enum AuthorizationGuidance: Equatable {
    /// `.notDetermined` — the only status where `LocationManager.start()` can still trigger
    /// an in-app system permission dialog.
    case promptInApp
    /// `.authorizedWhenInUse` / `.denied` / `.restricted` — iOS shows the when-in-use →
    /// always upgrade dialog at most once per app install (and never for denied/restricted),
    /// so re-prompting here is a silent no-op that would make the button look broken.
    /// Settings is the only reliable path to "Always" from any of these.
    case openSettings
    /// `.authorizedAlways` — already where we need to be; no banner.
    case none
}

func authorizationGuidance(for status: CLAuthorizationStatus) -> AuthorizationGuidance {
    switch status {
    case .authorizedAlways:
        return .none
    case .notDetermined:
        return .promptInApp
    case .authorizedWhenInUse, .denied, .restricted:
        return .openSettings
    @unknown default:
        return .openSettings
    }
}

/// Presentation logic for `ContentView`.
///
/// `ContentView` owns the SwiftUI/SwiftData property wrappers (`@Query`, `@Environment`)
/// that only work bound to a view's environment, and feeds their output through this type —
/// keeping the actual derivation (which stay is "current", what the permission banner should
/// say) in one pure, unit-testable place rather than scattered across view computed properties.
struct ContentViewModel {
    /// The country most recently detected — not necessarily the one with the most days.
    func current(in stays: [CountryStay]) -> CountryStay? {
        stays.max(by: { $0.lastSeen < $1.lastSeen })
    }

    func topStays(in stays: [CountryStay]) -> [CountryStay] {
        Array(stays.prefix(3))
    }

    func guidance(for status: CLAuthorizationStatus) -> AuthorizationGuidance {
        authorizationGuidance(for: status)
    }

    /// Footer text for the permission banner — the base explanation, plus Settings directions
    /// when that's the only path forward (see `AuthorizationGuidance.openSettings`).
    func footer(for status: CLAuthorizationStatus) -> String {
        let base = "CountryMe needs \"Always\" location access to keep tracking which country you're in, even when the app is closed."
        switch authorizationGuidance(for: status) {
        case .openSettings:
            return base + " Enable it in Settings → Privacy & Security → Location Services → CountryMe."
        case .promptInApp, .none:
            return base
        }
    }
}
