//
//  CountryStay.swift
//  CountryMe
//
//  Created by xdmGzDev on 08/06/2026.
//

import CoreLocation
import Foundation
import SwiftData

/// One record per distinct calendar day the user was detected in a given country.
///
/// CloudKit-compatible: every stored property has a default value, no `@Attribute(.unique)`
/// constraints. Uniqueness by `(countryCode, day)` is enforced in code via `recordDetection`.
@Model
final class CountryStay {
    #Index<CountryStay>([\.countryCode], [\.day], [\.countryCode, \.day])

    var countryCode: String = ""
    var countryName: String = ""
    /// Start-of-day (calendar-normalised) timestamp for this detection.
    var day: Date = Date.distantPast
    /// Where this detection occurred — decomposed into `Double` because `CLLocationCoordinate2D`
    /// isn't Codable/SwiftData-storable. `(0, 0)` is the "not recorded" sentinel.
    var latitude: Double = 0
    var longitude: Double = 0

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// `false` when the coordinate is the `(0, 0)` sentinel meaning "not recorded".
    var hasCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    init(
        countryCode: String = "",
        countryName: String = "",
        day: Date = .distantPast,
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    ) {
        self.countryCode = countryCode
        self.countryName = countryName
        self.day = day
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

/// Computed aggregate of all `CountryStay` records for a single country.
///
/// Built from a flat `[CountryStay]` array via `[CountryStay].summaries()` — not a SwiftData
/// model, purely a view-layer type. Defined here so both the app and the widget extension
/// can use it (this file is compiled into both targets).
struct CountrySummary: Identifiable, Hashable {
    var id: String { countryCode }
    let countryCode: String
    let countryName: String
    let dayCount: Int
    let firstSeen: Date
    let lastSeen: Date
}

extension [CountryStay] {
    /// Groups the receiver by `countryCode` and returns one `CountrySummary` per country,
    /// sorted by `dayCount` descending. Used by both `ContentViewModel` and the widget.
    func summaries() -> [CountrySummary] {
        let grouped = Dictionary(grouping: self, by: \.countryCode)
        return grouped.compactMap { code, group -> CountrySummary? in
            guard let name = group.first?.countryName else { return nil }
            return CountrySummary(
                countryCode: code,
                countryName: name,
                dayCount: group.count,
                firstSeen: group.map(\.day).min() ?? .distantPast,
                lastSeen: group.map(\.day).max() ?? .distantPast
            )
        }.sorted { $0.dayCount > $1.dayCount }
    }
}

// MARK: - Free functions

/// Records a single-day detection for a country.
///
/// Idempotent: calling it multiple times for the same `(countryCode, date)` produces exactly
/// one `CountryStay` row — subsequent calls on the same calendar day return the existing
/// record unchanged. This makes it safe to call from both the location stream and from
/// `fillMissingDays` without risk of double-counting.
@discardableResult
func recordDetection(
    countryCode: String,
    countryName: String,
    coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0),
    date: Date = .now,
    in context: ModelContext,
    calendar: Calendar = .current
) throws -> CountryStay {
    let startOfDay = calendar.startOfDay(for: date)
    let predicate = #Predicate<CountryStay> { $0.countryCode == countryCode && $0.day == startOfDay }
    var descriptor = FetchDescriptor<CountryStay>(predicate: predicate)
    descriptor.fetchLimit = 1

    if let existing = try context.fetch(descriptor).first {
        if !countryName.isEmpty {
            existing.countryName = countryName
        }
        return existing
    }

    let stay = CountryStay(
        countryCode: countryCode,
        countryName: countryName,
        day: startOfDay,
        coordinate: coordinate
    )
    context.insert(stay)
    return stay
}

/// Deletes every `CountryStay` for `code` and saves the context so the deletion is committed
/// to the local store and picked up by CloudKit sync. Calling this is the only step needed —
/// SwiftData's CloudKit integration propagates the deletion automatically on save.
func deleteHistory(for code: String, in context: ModelContext) throws {
    let predicate = #Predicate<CountryStay> { $0.countryCode == code }
    let stays = try context.fetch(FetchDescriptor<CountryStay>(predicate: predicate))
    stays.forEach { context.delete($0) }
    try context.save()
}

/// Fills in any calendar days that elapsed since the most-recent stay without a new detection.
///
/// Handles the stationary case: if the user didn't move overnight there is no location event
/// and no `CountryStay` is inserted for the new day. Called every time the app becomes active.
/// Safe to call repeatedly — a no-op when the most-recent stay is already today, or when no
/// stays exist yet.
func fillMissingDays(
    upTo date: Date = .now,
    in context: ModelContext,
    calendar: Calendar = .current
) throws {
    var descriptor = FetchDescriptor<CountryStay>(sortBy: [SortDescriptor(\.day, order: .reverse)])
    descriptor.fetchLimit = 1
    guard let mostRecent = try context.fetch(descriptor).first,
          mostRecent.day > .distantPast,
          !calendar.isDate(mostRecent.day, inSameDayAs: date) else {
        return
    }
    var day = calendar.date(byAdding: .day, value: 1, to: mostRecent.day)!
    let targetDay = calendar.startOfDay(for: date)
    while day <= targetDay {
        try recordDetection(
            countryCode: mostRecent.countryCode,
            countryName: mostRecent.countryName,
            coordinate: mostRecent.coordinate,
            date: day,
            in: context,
            calendar: calendar
        )
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
    }
}
