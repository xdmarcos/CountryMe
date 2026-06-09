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

struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.openURL) private var openURL
    @Query(sort: \CountryStay.day, order: .reverse) private var stays: [CountryStay]

    private let viewModel = ContentViewModel()

    @State private var selection: CountrySummary?

    private var summaries: [CountrySummary] {
        viewModel.summaries(from: stays)
    }

    private var current: CountrySummary? {
        viewModel.current(in: summaries)
    }

    private var topStays: [CountrySummary] {
        viewModel.topStays(in: summaries)
    }

    var body: some View {
        NavigationViewWrapper(selection: $selection) {
            list
                .navigationTitle("CountryMe")
        }
    }

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
        .navigationDestination(for: CountrySummary.self) { summary in
            CountryDetailView(summary: summary)
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
                ForEach(topStays) { summary in
                    row(for: summary)
                }
            }
        }

        switch viewModel.guidance(for: locationManager.authorizationStatus) {
        case .promptInApp:
            Section {
                Button("Allow Location Access") {
                    locationManager.start()
                }
            } footer: {
                Text(viewModel.footer(for: locationManager.authorizationStatus))
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
                Text(viewModel.footer(for: locationManager.authorizationStatus))
            }
        case .none:
            EmptyView()
        }

#if DEBUG
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

    @ViewBuilder
    private func row(for summary: CountrySummary) -> some View {
#if os(macOS)
        CountryRow(summary: summary)
            .tag(summary)
#else
        NavigationLink(value: summary) {
            CountryRow(summary: summary)
        }
#endif
    }
}

private struct CountryRow: View {
    let summary: CountrySummary

    var body: some View {
        HStack {
            Text(summary.countryCode.flagEmoji)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(summary.countryName)
                Text("\(summary.dayCount) day\(summary.dayCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    @Binding var selection: CountrySummary?
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            if let selection {
                CountryDetailView(summary: selection)
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
        .environment(LocationManager(modelContainer: try! ModelContainer(
            for: CountryStay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )))
        .modelContainer(for: CountryStay.self, inMemory: true)
}
