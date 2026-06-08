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

    /// The same-day dedup check (`calendar.isDate(existing.lastSeen, inSameDayAs:)`) is scoped
    /// to whichever `CountryStay` was fetched by `countryCode`, so it's inherently per-country —
    /// crossing from Spain into France into Andorra in a single day (a realistic scenario near
    /// borders) must count a day for *each* of them, not just the first or last detected.
    @Test func multipleCountriesOnSameDayAreEachCountedIndependently() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!
        let midday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 13))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: morning, in: context, calendar: calendar)
        try recordDetection(countryCode: "FR", countryName: "France", date: midday, in: context, calendar: calendar)
        try recordDetection(countryCode: "AD", countryName: "Andorra", date: evening, in: context, calendar: calendar)

        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 3)
        #expect(Set(stays.map(\.countryCode)) == ["ES", "FR", "AD"])

        let startOfDay = calendar.startOfDay(for: morning)
        for stay in stays {
            #expect(stay.dayCount == 1)
            let visitDays = stay.visitDays ?? []
            #expect(visitDays.count == 1)
            #expect(visitDays.first?.day == startOfDay)
            #expect(visitDays.count == stay.dayCount)
        }
    }

    /// A border-hopping day — Spain, then France, then back into Spain — must not inflate
    /// Spain's `dayCount`/`visitDays` a second time: the dedup check only looks at *that*
    /// country's `lastSeen`, and France's detection in between must not reset it.
    @Test func revisitingACountryAfterAnotherOnTheSameDayDoesNotDoubleCount() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 8))!
        let midday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 13))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20))!

        try recordDetection(countryCode: "ES", countryName: "Spain", date: morning, in: context, calendar: calendar)
        try recordDetection(countryCode: "FR", countryName: "France", date: midday, in: context, calendar: calendar)
        let spain = try recordDetection(countryCode: "ES", countryName: "Spain", date: evening, in: context, calendar: calendar)

        #expect(spain.dayCount == 1)
        #expect(spain.lastSeen == evening)
        #expect((spain.visitDays ?? []).count == 1)

        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 2)
        let france = try #require(stays.first { $0.countryCode == "FR" })
        #expect(france.dayCount == 1)
        #expect((france.visitDays ?? []).count == 1)
    }

    /// Real-world cross-timezone scenario: Spain (CEST, UTC+2) and Australia (AEST, UTC+10)
    /// are roughly eight hours apart. Production code passes `recordDetection` no explicit
    /// `calendar`, so it defaults to `.current` — which, on a real device, tracks the
    /// traveler's *current* time zone. A detection is therefore always judged against the
    /// local calendar of wherever it happened, so each country's "day" must be anchored to
    /// its own local calendar rather than a single shared reference — even when, in absolute
    /// (UTC) terms, the two detections land on different instants.
    @Test func distantTimeZoneCountriesOnTheSameTripAreEachCountedForTheirOwnLocalDay() throws {
        let context = try makeContext()

        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))

        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))

        // "The same day" to the traveler in each place — June 8th locally — despite an
        // ~8-hour zone offset putting them several hours apart in absolute time.
        let madridMorning = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 9)))
        let sydneyNight = try #require(sydney.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 22)))

        let spain = try recordDetection(countryCode: "ES", countryName: "Spain", date: madridMorning, in: context, calendar: madrid)
        let australia = try recordDetection(countryCode: "AU", countryName: "Australia", date: sydneyNight, in: context, calendar: sydney)

        #expect(spain.dayCount == 1)
        #expect(australia.dayCount == 1)
        #expect((spain.visitDays ?? []).first?.day == madrid.startOfDay(for: madridMorning))
        #expect((australia.visitDays ?? []).first?.day == sydney.startOfDay(for: sydneyNight))

        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 2)
    }

    /// A same-day detour through a far-away time zone must not disrupt the origin country's
    /// own day tracking: Spain in the morning, a side trip to Australia (recorded against
    /// Sydney's calendar, ~8 hours ahead), then back to Spain in the evening — still the
    /// same calendar day in Madrid. `existing.lastSeen` is an absolute instant, and each
    /// `recordDetection` call judges "same day" using *its own* calendar's time zone for
    /// both ends of the comparison, so the Australia detour (a different `CountryStay`,
    /// checked against Sydney's calendar) cannot leak into Spain's same-day determination.
    @Test func revisitingACountryAcrossADistantTimeZoneDetourStaysOnTheSameLocalDay() throws {
        let context = try makeContext()

        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))

        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))

        let madridMorning = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 7)))
        let sydneyAfternoon = try #require(sydney.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20)))
        let madridEvening = try #require(madrid.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 22)))

        try recordDetection(countryCode: "ES", countryName: "Spain", date: madridMorning, in: context, calendar: madrid)
        let australia = try recordDetection(countryCode: "AU", countryName: "Australia", date: sydneyAfternoon, in: context, calendar: sydney)
        let spain = try recordDetection(countryCode: "ES", countryName: "Spain", date: madridEvening, in: context, calendar: madrid)

        #expect(spain.dayCount == 1)
        #expect(spain.lastSeen == madridEvening)
        #expect((spain.visitDays ?? []).count == 1)

        #expect(australia.dayCount == 1)
        #expect((australia.visitDays ?? []).count == 1)

        let stays = try context.fetch(FetchDescriptor<CountryStay>())
        #expect(stays.count == 2)
    }
}
