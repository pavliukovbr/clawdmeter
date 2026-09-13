import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var petted = false

    /// One entry a minute keeps the countdowns honest, starting with a heart if Clawd was
    /// just petted.
    static func timeline(for snapshot: UsageSnapshot?, minutes: Int, now: Date = Date()) -> [UsageEntry] {
        var entries: [UsageEntry] = []
        var start = now
        if let pettedUntil = PetState.pettedUntil, pettedUntil > now {
            entries.append(UsageEntry(date: now, snapshot: snapshot, petted: true))
            start = pettedUntil
        }
        entries.append(UsageEntry(date: start, snapshot: snapshot))
        let nextMinute = Calendar.current.dateInterval(of: .minute, for: start)?.end ?? start.addingTimeInterval(60)
        for minute in 0..<minutes {
            entries.append(UsageEntry(date: nextMinute.addingTimeInterval(Double(minute) * 60), snapshot: snapshot))
        }
        return entries
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
