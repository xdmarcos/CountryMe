//
//  CountryStay.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import Foundation
import SwiftData

/// Tracks how many distinct calendar days the user has been detected in a given country.
///
/// CloudKit-compatible SwiftData model: every stored property has a default value, and
/// there are no `@Attribute(.unique)` constraints (CloudKit private databases don't support
/// them). Uniqueness by `countryCode` is enforced in code via `recordDetection`.
@Model
final class CountryStay {
    /// ISO 3166-1 alpha-2 country code, e.g. "ES".
    var countryCode: String = ""
    /// Localized display name, e.g. "Spain".
    var countryName: String = ""
    /// Number of distinct calendar days this country has been detected.
    var dayCount: Int = 0
    var firstSeen: Date = Date.distantPast
    var lastSeen: Date = Date.distantPast

    init(
        countryCode: String = "",
        countryName: String = "",
        dayCount: Int = 0,
        firstSeen: Date = .distantPast,
        lastSeen: Date = .distantPast
    ) {
        self.countryCode = countryCode
        self.countryName = countryName
        self.dayCount = dayCount
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Records a country detection, inserting a new `CountryStay` or updating the existing one
/// for that country code.
///
/// `dayCount` is incremented only the first time a country is seen on a given calendar day —
/// repeated detections on the same day update `lastSeen` but don't inflate the count. Kept as
/// a free function (rather than buried in `LocationManager`) so it can be unit tested with an
/// in-memory `ModelContext` without any CoreLocation involvement.
@discardableResult
func recordDetection(
    countryCode: String,
    countryName: String,
    date: Date = .now,
    in context: ModelContext,
    calendar: Calendar = .current
) throws -> CountryStay {
    let predicate = #Predicate<CountryStay> { $0.countryCode == countryCode }
    var descriptor = FetchDescriptor<CountryStay>(predicate: predicate)
    descriptor.fetchLimit = 1

    if let existing = try context.fetch(descriptor).first {
        if !calendar.isDate(existing.lastSeen, inSameDayAs: date) {
            existing.dayCount += 1
        }
        existing.lastSeen = date
        if !countryName.isEmpty {
            existing.countryName = countryName
        }
        return existing
    } else {
        let stay = CountryStay(
            countryCode: countryCode,
            countryName: countryName,
            dayCount: 1,
            firstSeen: date,
            lastSeen: date
        )
        context.insert(stay)
        return stay
    }
}
