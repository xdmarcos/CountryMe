//
//  CountryDetailView.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import SwiftUI
import SwiftData
import MapKit

struct CountryDetailView: View {
    private let viewModel: CountryDetailViewModel
    @Query private var days: [CountryStay]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var selectedDay: CountryStay?

    init(summary: CountrySummary) {
        viewModel = CountryDetailViewModel(summary: summary)
        let code = summary.countryCode
        _days = Query(
            filter: #Predicate<CountryStay> { $0.countryCode == code },
            sort: \CountryStay.day,
            order: .reverse
        )
    }

    private var summary: CountrySummary { viewModel.summary }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Text(summary.countryCode.flagEmoji)
                        .font(.system(size: 56))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.countryName)
                            .font(.title2.bold())
                        Text(viewModel.dayCountSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Summary") {
                LabeledContent("First seen", value: summary.firstSeen.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Last seen", value: summary.lastSeen.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Span", value: viewModel.spanSummary)
            }

            Section("History") {
                if days.isEmpty {
                    Text("No history recorded yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(days) { day in
                        DayHistoryRow(day: day) {
                            selectedDay = day
                        }
                    }
                }
            }

            Section {
                Button("Delete All History", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
            .confirmationDialog(
                "Delete all history for \(summary.countryName)?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete History", role: .destructive) {
                    deleteAllHistory()
                }
            } message: {
                Text("This will permanently remove all \(summary.dayCount) day\(summary.dayCount == 1 ? "" : "s") recorded for \(summary.countryName).")
            }
        }
        .navigationTitle(summary.countryName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $selectedDay) { day in
            DayLocationView(day: day)
        }
    }

    private func deleteAllHistory() {
        try? deleteHistory(for: summary.countryCode, in: modelContext)
        dismiss()
    }
}

// MARK: - History row

private struct DayHistoryRow: View {
    let day: CountryStay
    let onLocationTap: () -> Void

    var body: some View {
        HStack {
            Text(day.day.formatted(date: .complete, time: .omitted))
            Spacer()
            Button(action: onLocationTap) {
                Image(systemName: "location.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Full-screen location

private struct DayLocationView: View {
    let day: CountryStay
    @Environment(\.dismiss) private var dismiss

    private var cameraPosition: MapCameraPosition {
        guard day.hasCoordinate else { return .automatic }
        return .region(MKCoordinateRegion(
            center: day.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: cameraPosition) {
                if day.hasCoordinate {
                    Marker(day.day.formatted(date: .abbreviated, time: .omitted), coordinate: day.coordinate)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if !day.hasCoordinate {
                    Text("No precise location recorded for this day.")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(day.day.formatted(date: .complete, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CountryDetailView(summary: CountrySummary(
            countryCode: "ES",
            countryName: "Spain",
            dayCount: 3,
            firstSeen: .now.addingTimeInterval(-86_400 * 5),
            lastSeen: .now
        ))
    }
    .modelContainer(for: CountryStay.self, inMemory: true)
}
