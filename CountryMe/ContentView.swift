//
//  ContentView.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import SwiftUI
import SwiftData
import CoreLocation
#if os(iOS)
import UIKit
#endif

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

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.openURL) private var openURL
    @Query(sort: \CountryStay.dayCount, order: .reverse) private var stays: [CountryStay]

    /// Drives the macOS detail pane via `List(selection:)`; on iOS, drill-in is handled by
    /// `NavigationLink`/`navigationDestination` instead and this stays unused.
    @State private var selection: CountryStay?

    /// The country most recently detected — not necessarily the one with the most days.
    private var current: CountryStay? {
        stays.max(by: { $0.lastSeen < $1.lastSeen })
    }

    private var topStays: [CountryStay] {
        Array(stays.prefix(3))
    }

    private var authorizationFooter: String {
        let base = "CountryMe needs \"Always\" location access to keep tracking which country you're in, even when the app is closed."
        switch authorizationGuidance(for: locationManager.authorizationStatus) {
        case .openSettings:
            return base + " Enable it in Settings → Privacy & Security → Location Services → CountryMe."
        case .promptInApp, .none:
            return base
        }
    }

    var body: some View {
        NavigationViewWrapper(selection: $selection) {
            list
                .navigationTitle("CountryMe")
        }
    }

    /// The list of stays, platform-specific only in how taps drive navigation:
    /// `List(selection:)` + `.tag` feeds the macOS split-view detail pane, while iOS pushes
    /// via `NavigationLink`/`navigationDestination` inside a `NavigationStack`.
    @ViewBuilder
    private var list: some View {
#if os(macOS)
        List(selection: $selection) {
            sections
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
#else
        List {
            sections
        }
        .navigationDestination(for: CountryStay.self) { stay in
            CountryDetailView(stay: stay)
        }
#endif
    }

    @ViewBuilder
    private var sections: some View {
        Section("Current Country") {
            if let current {
                row(for: current)
            } else {
                Text("Not detected yet — move around a bit and CountryMe will pick it up.")
                    .foregroundStyle(.secondary)
            }
        }

        Section("Most Visited") {
            if topStays.isEmpty {
                Text("No data yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topStays) { stay in
                    row(for: stay)
                }
            }
        }

        // "Always" is required for proper behavior — significant-change monitoring only keeps
        // working while the app is suspended/closed under that authorization level.
        switch authorizationGuidance(for: locationManager.authorizationStatus) {
        case .promptInApp:
            Section {
                Button("Allow Location Access") {
                    locationManager.start()
                }
            } footer: {
                Text(authorizationFooter)
            }
        case .openSettings:
            Section {
#if os(iOS)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
#endif
            } footer: {
                Text(authorizationFooter)
            }
        case .none:
            EmptyView()
        }

#if DEBUG
        // DEV-ONLY — remove before shipping. Surfaces background-tracking internals
        // (last detection time, last error) so behavior on a real device is observable
        // without attaching a debugger.
        Section("Debug — Background Tracking") {
            LabeledContent("Authorization", value: "\(locationManager.authorizationStatus)")
            if let current {
                LabeledContent("Last detection", value: current.lastSeen.formatted(date: .abbreviated, time: .standard))
            } else {
                LabeledContent("Last detection", value: "none yet")
            }
            if let lastError = locationManager.lastError {
                LabeledContent("Last error", value: lastError)
                    .foregroundStyle(.red)
            }
        }
#endif
    }

    /// A tappable row for `stay`: tagged for `List` selection on macOS (feeds the split-view
    /// detail pane), or a `NavigationLink` push on iOS/visionOS (no split view there).
    @ViewBuilder
    private func row(for stay: CountryStay) -> some View {
#if os(macOS)
        CountryRow(stay: stay)
            .tag(stay)
#else
        NavigationLink(value: stay) {
            CountryRow(stay: stay)
        }
#endif
    }
}

/// A single country's flag, name, and day count — shared by the "current" and "most visited"
/// sections.
private struct CountryRow: View {
    let stay: CountryStay

    var body: some View {
        HStack {
            Text(stay.countryCode.flagEmoji)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(stay.countryName)
                Text("\(stay.dayCount) day\(stay.dayCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    @Binding var selection: CountryStay?
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            if let selection {
                CountryDetailView(stay: selection)
            } else {
                Text("Select a country")
            }
        }
#else
        NavigationStack {
            content()
        }
#endif
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager(modelContainer: try! ModelContainer(
            for: CountryStay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )))
        .modelContainer(for: CountryStay.self, inMemory: true)
}
