//
//  CountryMeTests.swift
//  CountryMeTests
//
//  Created by xdmGzDev on 08/06/2026.
//

import Testing
import Foundation
import SwiftData
@testable import CountryMe

/// Exercises `recordDetection`'s day-counting rules against an in-memory `ModelContext` —
/// no CoreLocation involved, so these run fast and deterministically.
@MainActor
struct CountryMeTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CountryStay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func newCountryInsertsWithDayCountOne() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)

        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context)

        #expect(stay.countryCode == "ES")
        #expect(stay.countryName == "Spain")
        #expect(stay.dayCount == 1)
        #expect(stay.firstSeen == date)
        #expect(stay.lastSeen == date)
    }

    @Test func sameCountrySameDayDoesNotIncrementDayCount() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: morning, in: context, calendar: calendar)
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: evening, in: context, calendar: calendar)

        #expect(stay.dayCount == 1)
        #expect(stay.lastSeen == evening)
    }

    @Test func sameCountryOnANewDayIncrementsDayCount() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 9))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: day1, in: context, calendar: calendar)
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: day2, in: context, calendar: calendar)

        #expect(stay.dayCount == 2)
        #expect(stay.firstSeen == day1)
        #expect(stay.lastSeen == day2)
    }

    @Test func differentCountriesGetSeparateRows() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 0)

        try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context)
        try recordDetection(countryCode: "FR", countryName: "France", date: date, in: context)

        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 2)
        #expect(Set(stays.map(\.countryCode)) == ["ES", "FR"])
    }
}
