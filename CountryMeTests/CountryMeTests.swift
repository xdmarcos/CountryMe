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
            for: CountryStay.self, VisitDay.self,
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

    @Test func newCountryCreatesOneVisitDay() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!

        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context, calendar: calendar)

        let visitDays = stay.visitDays ?? []
        #expect(visitDays.count == 1)
        #expect(visitDays.first?.day == calendar.startOfDay(for: date))
        #expect(visitDays.count == stay.dayCount)
    }

    @Test func sameCountrySameDayDoesNotAddAnotherVisitDay() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: morning, in: context, calendar: calendar)
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: evening, in: context, calendar: calendar)

        let visitDays = stay.visitDays ?? []
        #expect(visitDays.count == 1)
        #expect(visitDays.count == stay.dayCount)
    }

    @Test func sameCountryOnANewDayAddsAnotherVisitDay() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 9))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: day1, in: context, calendar: calendar)
        let stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: day2, in: context, calendar: calendar)

        let visitDays = (stay.visitDays ?? []).sorted { $0.day < $1.day }
        #expect(visitDays.count == 2)
        #expect(visitDays.map(\.day) == [calendar.startOfDay(for: day1), calendar.startOfDay(for: day2)])
        #expect(visitDays.count == stay.dayCount)
    }

    @Test func visitDayCountTracksDayCountAcrossManyDetections() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        var stay: CountryStay?

        // Two detections per day across four days — dayCount and visitDays.count should both
        // land on 4, never on 8.
        for day in 8...11 {
            for hour in [8, 20] {
                let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
                stay = try recordDetection(countryCode: "ES", countryName: "Spain", date: date, in: context, calendar: calendar)
            }
        }

        let result = try #require(stay)
        #expect(result.dayCount == 4)
        #expect((result.visitDays ?? []).count == 4)
        #expect((result.visitDays ?? []).count == result.dayCount)
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
