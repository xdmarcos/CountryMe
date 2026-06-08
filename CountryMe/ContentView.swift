//
//  ContentView.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import SwiftUI
import SwiftData
import CoreLocation

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Query(sort: \CountryStay.dayCount, order: .reverse) private var stays: [CountryStay]

    /// The country most recently detected — not necessarily the one with the most days.
    private var current: CountryStay? {
        stays.max(by: { $0.lastSeen < $1.lastSeen })
    }

    private var topStays: [CountryStay] {
        Array(stays.prefix(3))
    }

    var body: some View {
        NavigationViewWrapper {
            List {
                Section("Current Country") {
                    if let current {
                        CountryRow(stay: current)
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
                            CountryRow(stay: stay)
                        }
                    }
                }

                if locationManager.authorizationStatus == .notDetermined
                    || locationManager.authorizationStatus == .authorizedWhenInUse {
                    Section {
                        Button("Allow Location Access Always") {
                            locationManager.start()
                        }
                    } footer: {
                        Text("CountryMe needs \"Always\" location access to keep tracking which country you're in, even when the app is closed.")
                    }
                }
            }
            .navigationTitle("CountryMe")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
#endif
        }
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
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select a country")
        }
#else
        content()
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
