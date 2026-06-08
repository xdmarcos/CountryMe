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
    ///
    /// Stored (denormalized) rather than derived from `visitDays.count` so existing sort
    /// descriptors (`@Query`, the widget's `FetchDescriptor`) keep working without loading
    /// relationships, and so historical totals survive even for countries seen before
    /// per-day history existed. `recordDetection` keeps the two in lockstep going forward.
    var dayCount: Int = 0
    var firstSeen: Date = Date.distantPast
    var lastSeen: Date = Date.distantPast
    /// Per-day history, one row per distinct calendar day this country was detected.
    ///
    /// Optional to-many with an explicit inverse — required for CloudKit-compatible SwiftData
    /// models (relationships can't be required). Forward-only: rows recorded before this
    /// relationship existed have no `VisitDay` entries even though their `dayCount` reflects
    /// days seen at the time.
    @Relationship(deleteRule: .cascade, inverse: \VisitDay.country)
    var visitDays: [VisitDay]? = []

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

/// A single distinct calendar day on which a country was detected.
///
/// Child of `CountryStay.visitDays`, created by `recordDetection` whenever a detection
/// increments `dayCount` (i.e. the first detection of that country on a given calendar day).
/// CloudKit-compatible: defaulted properties, optional inverse relationship, no uniqueness
/// constraint (uniqueness-by-day-per-country is enforced in code by `recordDetection`, which
/// only appends when `dayCount` itself increments).
@Model
final class VisitDay {
    /// Start-of-day (calendar-normalized) timestamp this country was detected on.
    var day: Date = Date.distantPast
    var country: CountryStay?

    init(day: Date = .distantPast, country: CountryStay? = nil) {
        self.day = day
        self.country = country
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
            let visitDay = VisitDay(day: calendar.startOfDay(for: date), country: existing)
            context.insert(visitDay)
            existing.visitDays?.append(visitDay)
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
        let visitDay = VisitDay(day: calendar.startOfDay(for: date), country: stay)
        context.insert(visitDay)
        stay.visitDays?.append(visitDay)
        return stay
    }
}
