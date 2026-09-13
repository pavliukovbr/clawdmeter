import SwiftUI
import WidgetKit

@main
struct ClawdmeterWidgets: WidgetBundle {
    var body: some Widget {
        ClawdmeterWidget()
    }
}

struct ClawdmeterWidget: Widget {
    static let kind = "ClawdmeterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UsageProvider()) { entry in
            UsageEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your plan limits at a glance, with Clawd keeping you company.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var petted = false
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = SnapshotStore.load()
        completion(UsageEntry(date: .now, snapshot: snapshot ?? (context.isPreview ? .preview : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = SnapshotStore.load()
        let now = Date()
        var entries: [UsageEntry] = []
        var start = now

        if let pettedUntil = PetState.pettedUntil, pettedUntil > now {
            entries.append(UsageEntry(date: now, snapshot: snapshot, petted: true))
            start = pettedUntil
        }
        entries.append(UsageEntry(date: start, snapshot: snapshot))

        // One entry a minute keeps the countdowns honest. The app reloads the
        // timeline whenever the numbers change, so an hour ahead is plenty.
        let nextMinute = Calendar.current.dateInterval(of: .minute, for: start)?.end ?? start.addingTimeInterval(60)
        for minute in 0..<60 {
            entries.append(UsageEntry(date: nextMinute.addingTimeInterval(Double(minute) * 60), snapshot: snapshot))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct UsageEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(
            layout: family == .systemMedium ? .medium : .small,
            snapshot: entry.snapshot,
            date: entry.date,
            petted: entry.petted
        )
        .environment(\.interactivePet, true)
        .containerBackground(for: .widget) {
            Palette.background
        }
    }
}
