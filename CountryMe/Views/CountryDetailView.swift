//
//  CountryDetailView.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import SwiftUI
import SwiftData

/// Drill-in detail screen for a single country: summary stats plus, where available, a
/// day-by-day history.
///
/// `visitDays` only exists going forward from when per-day history was introduced — countries
/// detected before that still show an accurate `dayCount` but may have a sparse or empty
/// history list. That's expected, not a bug; the empty-state message below explains it.
struct CountryDetailView: View {
    private let viewModel: CountryDetailViewModel

    init(stay: CountryStay) {
        viewModel = CountryDetailViewModel(stay: stay)
    }

    private var stay: CountryStay { viewModel.stay }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Text(stay.countryCode.flagEmoji)
                        .font(.system(size: 56))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stay.countryName)
                            .font(.title2.bold())
                        Text(viewModel.dayCountSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Summary") {
                LabeledContent("First seen", value: stay.firstSeen.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Last seen", value: stay.lastSeen.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Span", value: viewModel.spanSummary)
            }

            Section("History") {
                if viewModel.sortedVisitDays.isEmpty {
                    Text("No day-by-day history recorded yet — CountryMe only started keeping a detailed log recently, so older stays only have a running total.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.sortedVisitDays) { visitDay in
                        Text(visitDay.day.formatted(date: .complete, time: .omitted))
                    }
                }
            }
        }
        .navigationTitle(stay.countryName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview {
    NavigationStack {
        CountryDetailView(stay: {
            let stay = CountryStay(countryCode: "ES", countryName: "Spain", dayCount: 3, firstSeen: .now.addingTimeInterval(-86_400 * 5), lastSeen: .now)
            stay.visitDays = [
                VisitDay(day: Calendar.current.startOfDay(for: .now), country: stay),
                VisitDay(day: Calendar.current.startOfDay(for: .now.addingTimeInterval(-86_400 * 2)), country: stay),
                VisitDay(day: Calendar.current.startOfDay(for: .now.addingTimeInterval(-86_400 * 5)), country: stay)
            ]
            return stay
        }())
    }
}
