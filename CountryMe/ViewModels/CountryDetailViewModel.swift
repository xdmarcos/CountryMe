//
//  CountryDetailViewModel.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation

/// Presentation logic for `CountryDetailView`.
struct CountryDetailViewModel {
    let summary: CountrySummary

    var dayCountSummary: String {
        "\(summary.dayCount) day\(summary.dayCount == 1 ? "" : "s") spent here"
    }

    var spanDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: summary.firstSeen, to: summary.lastSeen).day ?? 0)
    }

    var spanSummary: String {
        "\(spanDays) day\(spanDays == 1 ? "" : "s")"
    }
}
