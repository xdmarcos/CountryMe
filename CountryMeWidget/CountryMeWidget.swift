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
    let current: CountrySummary?
    let topStays: [CountrySummary]
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
        // Mirrors LocationManager.checkDayRollover(): backfill any days that elapsed since the
        // last detection so the count keeps advancing even if the app is never opened — every
        // timeline refresh becomes a rollover check.
        try? fillMissingDays(in: context)
        try? context.save()
        let stays = (try? context.fetch(FetchDescriptor<CountryStay>())) ?? []
        let summaries = stays.summaries()
        let current = summaries.max { $0.lastSeen < $1.lastSeen }
        return CountryMeEntry(date: .now, current: current, topStays: Array(summaries.prefix(8)))
    }
}

struct CountryMeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CountryMeEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
#if os(iOS)
        case .accessoryInline:
            inlineAccessoryView
        case .accessoryCircular:
            circularAccessoryView
        case .accessoryRectangular:
            rectangularAccessoryView
#endif
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Current")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let current = entry.current {
                Text(current.countryCode.flagEmoji)
                    .font(.system(size: 40))
                Text(current.countryName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(current.dayCount)d")
                    .foregroundStyle(.secondary)
            } else {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let current = entry.current {
                    Text(current.countryCode.flagEmoji)
                        .font(.system(size: 36))
                    Text(current.countryName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(current.dayCount)d")
                        .foregroundStyle(.secondary)
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
                    ForEach(entry.topStays.prefix(3)) { summary in
                        listRow(for: summary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 6) {
                if let current = entry.current {
                    Text(current.countryCode.flagEmoji)
                        .font(.system(size: 28))
                    Text(current.countryName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(current.dayCount)d")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            Text("Most Visited")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.topStays.isEmpty {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.topStays) { summary in
                        listRow(for: summary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listRow(for summary: CountrySummary) -> some View {
        HStack(spacing: 6) {
            Text(summary.countryCode.flagEmoji)
            Text(summary.countryName)
                .lineLimit(1)
            Spacer()
            Text("\(summary.dayCount)d")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

#if os(iOS)
    private var inlineAccessoryView: some View {
        Group {
            if let current = entry.current {
                Text("\(current.countryCode.flagEmoji) \(current.countryName)")
            } else {
                Text("CountryMe")
            }
        }
    }

    private var circularAccessoryView: some View {
        VStack(spacing: 0) {
            if let current = entry.current {
                Text(current.countryCode.flagEmoji)
                    .font(.title3)
                Text("\(current.dayCount)d")
                    .font(.caption2)
            } else {
                Image(systemName: "globe")
                    .font(.title3)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularAccessoryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CountryMe")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let current = entry.current {
                Text("\(current.countryCode.flagEmoji) \(current.countryName)")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(current.dayCount) day\(current.dayCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No data yet")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
#endif
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
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
#if os(iOS)
        families += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
#endif
        return families
    }
}

#Preview(as: .systemMedium) {
    CountryMeWidget()
} timeline: {
    CountryMeEntry(date: .now, current: nil, topStays: [])
}
