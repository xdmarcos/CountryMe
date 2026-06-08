//
//  CountryStay.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import CoreLocation
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
    /// Where this detection occurred, decomposed into `Double` components — `CLLocationCoordinate2D`
    /// itself isn't `Codable`/storable in SwiftData. `(0, 0)` (off the coast of Ghana) is the
    /// "not recorded" sentinel for rows created before this existed, mirroring `CountryStay`'s
    /// use of `.distantPast` for unknown dates. Recorded so a detection can later be checked
    /// against the claimed country's actual borders — reverse geocoding can misattribute points
    /// near coastlines and land borders.
    var latitude: Double = 0
    var longitude: Double = 0
    var country: CountryStay?

    /// Convenience view of `latitude`/`longitude` for use with CoreLocation/MapKit APIs.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        day: Date = .distantPast,
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0),
        country: CountryStay? = nil
    ) {
        self.day = day
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.country = country
    }
}

/// Records a country detection, inserting a new `CountryStay` or updating the existing one
/// for that country code.
///
/// `dayCount` is incremented only the first time a country is seen on a given calendar day —
/// repeated detections on the same day update `lastSeen` but don't inflate the count. Kept as
/// a free function (rather than buried in `LocationManager`) so it can be unit tested with an
/// in-memory `ModelContext` without any location-services involvement — `coordinate` is a
/// plain value type, trivial to construct in tests without `CLLocationManager`/permissions.
@discardableResult
func recordDetection(
    countryCode: String,
    countryName: String,
    coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0),
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
            let visitDay = VisitDay(day: calendar.startOfDay(for: date), coordinate: coordinate, country: existing)
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
        let visitDay = VisitDay(day: calendar.startOfDay(for: date), coordinate: coordinate, country: stay)
        context.insert(visitDay)
        stay.visitDays?.append(visitDay)
        return stay
    }
}
