import SwiftUI
import WidgetKit

@main
struct ClawdmeterPhoneWidgets: WidgetBundle {
    var body: some Widget {
        HomeUsageWidget()
        LockUsageWidget()
        UsageLiveActivity()
    }
}

struct PhoneUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: .now, snapshot: PhoneVault.lastReply?.reply.snapshot ?? .preview))
            return
        }
        Task {
            let result = await UsageRefresher.refresh()
            completion(UsageEntry(date: .now, snapshot: result.stored?.reply.snapshot))
        }
    }

    /// Each reload asks the Mac for fresh numbers. iOS limits how often widgets reload, so
    /// the minute entries in between keep the countdowns moving.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let result = await UsageRefresher.refresh()
            let entries = UsageEntry.timeline(for: result.stored?.reply.snapshot, minutes: 30)
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct HomeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClawdmeterHome", provider: PhoneUsageProvider()) { entry in
            UsageEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your plan limits at a glance, with Clawd keeping you company.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct LockUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClawdmeterLock", provider: PhoneUsageProvider()) { entry in
            LockUsageView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Claude Session")
        .description("Your current session on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockUsageView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        let summary = UsageSummary(snapshot: entry.snapshot, date: entry.date)
        let primary = summary.primary

        switch family {
        case .accessoryCircular:
            Gauge(value: primary.fraction) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 1) {
                    ClawdView(mood: summary.mood, unit: 1.2, color: .white, eyeColor: .clear, animated: false)
                    Text(primary.value)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.7)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    ClawdView(mood: summary.mood, unit: 1, color: .white, eyeColor: .clear, animated: false)
                    Text(primary.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(primary.value)
                        .font(.system(.headline, design: .rounded))
                }
                Gauge(value: primary.fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
                Text(primary.detail ?? summary.planName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        default:
            if let reset = primary.detail {
                Text("\(primary.title) \(primary.value), \(reset.lowercased())")
            } else {
                Text("\(primary.title) \(primary.value)")
            }
        }
    }
}
