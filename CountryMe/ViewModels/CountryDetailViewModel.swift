//
//  CountryDetailViewModel.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation

/// Presentation logic for `CountryDetailView`: formats `CountryStay`/`VisitDay` data for
/// display without any SwiftUI dependency, so it's testable in isolation.
struct CountryDetailViewModel {
    let stay: CountryStay

    var sortedVisitDays: [VisitDay] {
        (stay.visitDays ?? []).sorted { $0.day > $1.day }
    }

    /// Whole days between first and last detection — a rough "span" independent of `dayCount`
    /// (which counts *distinct* days, not the length of the date range).
    var spanDays: Int {
        Calendar.current.dateComponents([.day], from: stay.firstSeen, to: stay.lastSeen).day ?? 0
    }

    var dayCountSummary: String {
        "\(stay.dayCount) day\(stay.dayCount == 1 ? "" : "s") spent here"
    }

    var spanSummary: String {
        "\(spanDays) day\(spanDays == 1 ? "" : "s")"
    }
}
