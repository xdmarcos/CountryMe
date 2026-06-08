//
//  CountryMeWidget.swift
//  CountryMeWidget
//
//  Created by xdmGzDev on 08/06/2026.
//

import WidgetKit
import SwiftUI
import SwiftData

struct CountryMeEntry: TimelineEntry {
    let date: Date
    let current: CountryStay?
    let topStays: [CountryStay]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CountryMeEntry {
        CountryMeEntry(date: .now, current: nil, topStays: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CountryMeEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountryMeEntry>) -> Void) {
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [makeEntry()], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> CountryMeEntry {
        let context = ModelContext(SharedModelContainer.shared)
        let descriptor = FetchDescriptor<CountryStay>(sortBy: [SortDescriptor(\.dayCount, order: .reverse)])
        let stays = (try? context.fetch(descriptor)) ?? []
        let current = stays.max { $0.lastSeen < $1.lastSeen }
        return CountryMeEntry(date: .now, current: current, topStays: Array(stays.prefix(3)))
    }
}

struct CountryMeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CountryMeEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let current = entry.current {
                Text(current.countryCode.flagEmoji)
                    .font(.system(size: 40))
                Text(current.countryName)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let current = entry.current {
                    Text(current.countryCode.flagEmoji)
                        .font(.system(size: 36))
                    Text(current.countryName)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Most Visited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.topStays.isEmpty {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.topStays) { stay in
                        HStack(spacing: 6) {
                            Text(stay.countryCode.flagEmoji)
                            Text(stay.countryName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(stay.dayCount)d")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CountryMeWidget: Widget {
    let kind: String = "CountryMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CountryMeWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CountryMe")
        .description("Shows your current country and most visited countries.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    CountryMeWidget()
} timeline: {
    CountryMeEntry(date: .now, current: nil, topStays: [])
}
