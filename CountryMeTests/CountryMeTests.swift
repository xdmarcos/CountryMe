//
//  CountryMeTests.swift
//  CountryMeTests
//
//  Created by xdmGzDev on 08/06/2026.
//

import Testing
import Foundation
import CoreLocation
import SwiftData

@testable import CountryMe

/// Exercises `recordDetection`, `fillMissingDays`, and `deleteHistory` against an in-memory
/// `ModelContext`. Swift Testing creates a fresh struct instance per test, so each `@Test`
/// automatically gets an isolated context.
@MainActor
struct CountryMeTests {
    let context: ModelContext
    let calendar = Calendar(identifier: .gregorian)

    init() throws {
        let container = try ModelContainer(
            for: CountryStay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func stayCount(for code: String) throws -> Int {
        let predicate = #Predicate<CountryStay> { $0.countryCode == code }
        return try context.fetchCount(FetchDescriptor<CountryStay>(predicate: predicate))
    }

    // MARK: - recordDetection

    @Test func newCountryInsertsOneStay() throws {
        let date = Date(timeIntervalSince1970: 0)
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context)
        #expect(stay.countryCode == "ES")
        #expect(stay.countryName == "Spain")
        #expect(try stayCount(for: "ES") == 1)
    }

    @Test func sameCountrySameDayIsIdempotent() throws {
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20)))
        try recordDetection(countryCode: "ES", countryName: "Spain", date: morning, in: context, calendar: calendar)
        try recordDetection(countryCode: "ES", countryName: "Spain", date: evening, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 1)
    }

    @Test func sameCountryOnNewDayAddsAnotherStay() throws {
        let day1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let day2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9)))
        try recordDetection(countryCode: "ES", countryName: "Spain", date: day1, in: context, calendar: calendar)
        try recordDetection(countryCode: "ES", countryName: "Spain", date: day2, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 2)
    }

    @Test func multipleDetectionsPerDayDoNotMultiply() throws {
        // Two detections per day across four days — should produce exactly 4 stays, not 8.
        for day in 8...11 {
            for hour in [8, 20] {
                let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour)))
                try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context, calendar: calendar)
            }
        }
        #expect(try stayCount(for: "ES") == 4)
    }

    @Test func stayDayIsNormalisedToStartOfDay() throws {
        let midday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 13)))
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: midday, in: context, calendar: calendar)
        #expect(stay.day == calendar.startOfDay(for: midday))
    }

    @Test func differentCountriesGetSeparateRows() throws {
        let date = Date(timeIntervalSince1970: 0)
        try recordDetection(countryCode: "ES", countryName: "Spain",  date: date, in: context)
        try recordDetection(countryCode: "FR", countryName: "France", date: date, in: context)
        #expect(try stayCount(for: "ES") == 1)
        #expect(try stayCount(for: "FR") == 1)
    }

    /// Spain, France, Andorra — all detected on the same day — must each get one stay.
    @Test func multipleCountriesOnSameDayAreEachCountedIndependently() throws {
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8)))
        let midday  = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 13)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20)))
        try recordDetection(countryCode: "ES", countryName: "Spain",   date: morning, in: context, calendar: calendar)
        try recordDetection(countryCode: "FR", countryName: "France",  date: midday,  in: context, calendar: calendar)
        try recordDetection(countryCode: "AD", countryName: "Andorra", date: evening, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 1)
        #expect(try stayCount(for: "FR") == 1)
        #expect(try stayCount(for: "AD") == 1)
        let allStays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(Set(allStays.map(\.day)) == [calendar.startOfDay(for: morning)])
    }

    /// Spain → France → Spain on the same day must not create a second stay for Spain.
    @Test func revisitingACountryOnSameDayDoesNotDoubleCount() throws {
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8)))
        let midday  = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 13)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20)))
        try recordDetection(countryCode: "ES", countryName: "Spain",  date: morning, in: context, calendar: calendar)
        try recordDetection(countryCode: "FR", countryName: "France", date: midday,  in: context, calendar: calendar)
        try recordDetection(countryCode: "ES", countryName: "Spain",  date: evening, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 1)
        #expect(try stayCount(for: "FR") == 1)
    }

    // MARK: - CountrySummary aggregation

    @Test func summariesComputeDayCount() throws {
        for day in 8...10 {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day)))
            try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context, calendar: calendar)
        }
        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        let summary = try #require(stays.summaries().first { $0.countryCode == "ES" })
        #expect(summary.dayCount == 3)
    }

    @Test func summariesComputeFirstAndLastSeen() throws {
        let day1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let day2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9)))
        try recordDetection(countryCode: "ES", countryName: "Spain", date: day1, in: context, calendar: calendar)
        try recordDetection(countryCode: "ES", countryName: "Spain", date: day2, in: context, calendar: calendar)
        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        let summary = try #require(stays.summaries().first { $0.countryCode == "ES" })
        #expect(summary.firstSeen == calendar.startOfDay(for: day1))
        #expect(summary.lastSeen  == calendar.startOfDay(for: day2))
    }

    // MARK: - deleteHistory

    @Test func deleteHistoryRemovesAllStaysForThatCountry() throws {
        for day in 8...10 {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day)))
            try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context, calendar: calendar)
        }
        #expect(try stayCount(for: "ES") == 3)
        try deleteHistory(for: "ES", in: context)
        #expect(try stayCount(for: "ES") == 0)
    }

    @Test func deleteHistoryDoesNotAffectOtherCountries() throws {
        let date = Date(timeIntervalSince1970: 0)
        try recordDetection(countryCode: "ES", countryName: "Spain",  date: date, in: context)
        try recordDetection(countryCode: "FR", countryName: "France", date: date, in: context)
        try deleteHistory(for: "ES", in: context)
        #expect(try stayCount(for: "ES") == 0)
        #expect(try stayCount(for: "FR") == 1)
    }

    @Test func deleteHistoryIsNoOpForUnknownCountry() throws {
        let date = Date(timeIntervalSince1970: 0)
        try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context)
        try deleteHistory(for: "XX", in: context)
        #expect(try stayCount(for: "ES") == 1)
    }

    @Test func deleteHistoryLeavesNoOrphanedRows() throws {
        for day in 8...10 {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day)))
            try recordDetection(countryCode: "ES", countryName: "Spain",  date: date, in: context, calendar: calendar)
            try recordDetection(countryCode: "FR", countryName: "France", date: date, in: context, calendar: calendar)
        }
        try deleteHistory(for: "ES", in: context)
        let remaining = try context.fetchCount(FetchDescriptor<CountryStay>())
        #expect(remaining == 3) // only FR's 3 days remain
    }

    // MARK: - fillMissingDays

    @Test func dayRolloverIsRecordedWhenUserRemainsStationary() throws {
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 14)))
        let today     = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        try recordDetection(countryCode: "ES", countryName: "Spain", date: yesterday, in: context, calendar: calendar)
        try fillMissingDays(upTo: today, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 2)
    }

    @Test func dayRolloverFillsAllMissingDays() throws {
        let threeDaysAgo = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 14)))
        let today        = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        try recordDetection(countryCode: "AU", countryName: "Australia", date: threeDaysAgo, in: context, calendar: calendar)
        try fillMissingDays(upTo: today, in: context, calendar: calendar)
        #expect(try stayCount(for: "AU") == 4) // June 6, 7, 8, 9
    }

    @Test func dayRolloverIsNoOpWhenAlreadyUpToDate() throws {
        let now        = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        let laterToday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 16)))
        try recordDetection(countryCode: "ES", countryName: "Spain", date: now, in: context, calendar: calendar)
        try fillMissingDays(upTo: laterToday, in: context, calendar: calendar)
        #expect(try stayCount(for: "ES") == 1)
    }

    @Test func dayRolloverInheritsCoordinateFromMostRecentStay() throws {
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 14)))
        let today     = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        let madrid    = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        try recordDetection(countryCode: "ES", countryName: "Spain", coordinate: madrid, date: yesterday, in: context, calendar: calendar)
        try fillMissingDays(upTo: today, in: context, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let predicate  = #Predicate<CountryStay> { $0.day == todayStart }
        let fetched    = try context.fetch(FetchDescriptor<CountryStay>(predicate: predicate))
        let filledStay = try #require(fetched.first, "Expected a rollover stay for today")
        #expect(filledStay.latitude  == madrid.latitude)
        #expect(filledStay.longitude == madrid.longitude)
    }

    @Test func dayRolloverOnlyFillsMostRecentCountry() throws {
        let twoDaysAgo = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 9)))
        let yesterday  = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 18)))
        let today      = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        try recordDetection(countryCode: "ES", countryName: "Spain",     date: twoDaysAgo, in: context, calendar: calendar)
        try recordDetection(countryCode: "AU", countryName: "Australia", date: yesterday,  in: context, calendar: calendar)
        try fillMissingDays(upTo: today, in: context, calendar: calendar)
        // AU was detected most recently → today gets added to AU, not ES
        #expect(try stayCount(for: "AU") == 2)
        #expect(try stayCount(for: "ES") == 1)
    }

    // MARK: - Coordinate invariant

    /// Asserts every `CountryStay` in the store carries a valid coordinate.
    /// `sourceLocation` is forwarded so failure messages point to the call site.
    private func assertAllStaysHaveCoordinates(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        for stay in stays {
            #expect(stay.hasCoordinate, "\(stay.countryCode) stay on \(stay.day) has no coordinate", sourceLocation: sourceLocation)
        }
    }

    @Test(arguments: [
        (lat:  40.4168, lon:  -3.7038),   // Madrid
        (lat:  48.8566, lon:   2.3522),   // Paris
        (lat: -33.8688, lon: 151.2093),   // Sydney
    ])
    func recordDetectionStoresProvidedCoordinate(coord: (lat: Double, lon: Double)) throws {
        let location = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
        let stay = try recordDetection(countryCode: "XX", countryName: "Test", coordinate: location, date: .now, in: context)
        #expect(stay.latitude  == coord.lat, "Stored latitude must match what was recorded")
        #expect(stay.longitude == coord.lon, "Stored longitude must match what was recorded")
        #expect(stay.hasCoordinate, "Any stay created by recordDetection must carry a valid coordinate")
    }

    @Test func allStaysHaveCoordinatesAfterDirectDetections() throws {
        let coords: [(String, CLLocationCoordinate2D)] = [
            ("ES", CLLocationCoordinate2D(latitude:  40.4168, longitude:  -3.7038)),
            ("FR", CLLocationCoordinate2D(latitude:  48.8566, longitude:   2.3522)),
            ("AU", CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)),
        ]
        for (day, (code, coord)) in zip(8..., coords) {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day)))
            try recordDetection(countryCode: code, countryName: code, coordinate: coord, date: date, in: context, calendar: calendar)
        }
        try assertAllStaysHaveCoordinates()
    }

    @Test func allFilledDaysInheritCoordinate() throws {
        let threeDaysAgo = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 14)))
        let today        = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        let sydney       = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        try recordDetection(countryCode: "AU", countryName: "Australia", coordinate: sydney, date: threeDaysAgo, in: context, calendar: calendar)
        try fillMissingDays(upTo: today, in: context, calendar: calendar)
        // 4 stays total (June 6–9); every one must carry the Sydney coordinate.
        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 4, "Expected 4 stays for June 6–9")
        for stay in stays {
            #expect(stay.hasCoordinate,               "\(stay.countryCode) stay on \(stay.day) is missing a coordinate")
            #expect(stay.latitude  == sydney.latitude,  "Filled stay must inherit source latitude")
            #expect(stay.longitude == sydney.longitude, "Filled stay must inherit source longitude")
        }
    }

    @Test func allStaysHaveCoordinatesAfterDetectionsAndRollover() throws {
        let madrid = CLLocationCoordinate2D(latitude:  40.4168, longitude: -3.7038)
        let paris  = CLLocationCoordinate2D(latitude:  48.8566, longitude:  2.3522)
        // Day 1 in Madrid, day 2 in Paris, app inactive for two days → rollover fills days 3–4 for Paris.
        let day1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6)))
        let day2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let day4 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10)))
        try recordDetection(countryCode: "ES", countryName: "Spain",  coordinate: madrid, date: day1, in: context, calendar: calendar)
        try recordDetection(countryCode: "FR", countryName: "France", coordinate: paris,  date: day2, in: context, calendar: calendar)
        try fillMissingDays(upTo: day4, in: context, calendar: calendar)
        try assertAllStaysHaveCoordinates()
    }

    // MARK: - Timezone scenarios

    /// A detection on "June 8th in Madrid" and "June 8th in Sydney" must each produce one
    /// stay, with `day` normalised to the respective local midnight.
    @Test func distantTimeZoneCountriesOnTheSameTripAreEachCountedForTheirOwnLocalDay() throws {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let madridMorning = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 9)))
        let sydneyNight   = try #require(sydney.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 22)))
        let spain     = try recordDetection(countryCode: "ES", countryName: "Spain",     date: madridMorning, in: context, calendar: madrid)
        let australia = try recordDetection(countryCode: "AU", countryName: "Australia", date: sydneyNight,   in: context, calendar: sydney)
        #expect(spain.day     == madrid.startOfDay(for: madridMorning))
        #expect(australia.day == sydney.startOfDay(for: sydneyNight))
        #expect(try stayCount(for: "ES") == 1)
        #expect(try stayCount(for: "AU") == 1)
    }

    /// Spain → Australia side trip → back to Spain, still the same calendar day in Madrid.
    /// The Australia detection must not interfere with Spain's same-day dedup.
    @Test func revisitingACountryAcrossADistantTimeZoneDetourStaysOnTheSameLocalDay() throws {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let madridMorning   = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 7)))
        let sydneyAfternoon = try #require(sydney.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20)))
        let madridEvening   = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 22)))
        try recordDetection(countryCode: "ES", countryName: "Spain",     date: madridMorning,   in: context, calendar: madrid)
        try recordDetection(countryCode: "AU", countryName: "Australia", date: sydneyAfternoon, in: context, calendar: sydney)
        try recordDetection(countryCode: "ES", countryName: "Spain",     date: madridEvening,   in: context, calendar: madrid)
        #expect(try stayCount(for: "ES") == 1)
        #expect(try stayCount(for: "AU") == 1)
    }
}
