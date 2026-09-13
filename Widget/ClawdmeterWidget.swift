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

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = SnapshotStore.load()
        completion(UsageEntry(date: .now, snapshot: snapshot ?? (context.isPreview ? .preview : nil)))
    }

    /// The app reloads the timeline whenever the numbers change, so an hour ahead is plenty.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entries = UsageEntry.timeline(for: SnapshotStore.load(), minutes: 60)
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
