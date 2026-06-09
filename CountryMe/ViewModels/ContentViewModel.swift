//
//  ContentViewModel.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import CoreLocation

/// How the "needs Always access" banner should guide the user for a given authorization status.
enum AuthorizationGuidance: Equatable {
    case promptInApp
    case openSettings
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
struct ContentViewModel {
    func summaries(from stays: [CountryStay]) -> [CountrySummary] {
        stays.summaries()
    }

    /// The country most recently detected — not necessarily the one with the most days.
    func current(in summaries: [CountrySummary]) -> CountrySummary? {
        summaries.max(by: { $0.lastSeen < $1.lastSeen })
    }

    func topStays(in summaries: [CountrySummary]) -> [CountrySummary] {
        Array(summaries.prefix(3))
    }

    func guidance(for status: CLAuthorizationStatus) -> AuthorizationGuidance {
        authorizationGuidance(for: status)
    }

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
