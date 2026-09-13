import SwiftUI
import WidgetKit

struct UsageWidgetView: View {
    enum Layout {
        case small, medium
    }

    var layout: Layout
    var snapshot: UsageSnapshot?
    var date: Date
    var petted = false

    var body: some View {
        let summary = UsageSummary(snapshot: snapshot, date: date)
        switch layout {
        case .small:
            PrimaryPanel(summary: summary, petted: petted, showsFooter: true)
                .padding(15)
        case .medium:
            HStack(spacing: 0) {
                PrimaryPanel(summary: summary, petted: petted, showsFooter: false, petUnit: 3.5)
                    .frame(width: 142)
                    .padding(.trailing, 15)
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                DetailPanel(summary: summary)
                    .padding(.leading, 15)
            }
            .padding(15)
        }
    }
}

// MARK: Primary

private struct PrimaryPanel: View {
    var summary: UsageSummary
    var petted: Bool
    var showsFooter: Bool
    var petUnit: CGFloat = 3

    @Environment(\.interactivePet) private var interactivePet

    var body: some View {
        let primary = summary.primary
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.planName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(Palette.clayLight)
                .widgetAccentable()
                .lineLimit(1)

            Text(primary.value)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: primary.fraction))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 1)

            HStack(spacing: 4) {
                Text(primary.title)
                    .foregroundStyle(.white.opacity(0.9))
                if let short = shortDetail(primary) {
                    Text(short)
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            PetTrack(
                fraction: primary.fraction,
                severity: primary.severity,
                mood: petted ? .happy : summary.mood,
                unit: petUnit
            )
            .overlay {
                if interactivePet {
                    Button(intent: PetClawdIntent()) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsFooter {
                footer
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shortDetail(_ metric: UsageSummary.Metric) -> String? {
        guard let detail = metric.detail else { return nil }
        return detail
            .replacingOccurrences(of: "Resets in ", with: "")
            .replacingOccurrences(of: "Resets ", with: "")
    }

    @ViewBuilder
    private var footer: some View {
        if let note = summary.note {
            Text(note)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if !summary.secondary.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(summary.secondary.prefix(2).enumerated()), id: \.element.id) { index, metric in
                    if index > 0 { Spacer(minLength: 6) }
                    HStack(spacing: 3) {
                        Text(metric.shortTitle ?? metric.title)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(metric.value)
                            .foregroundStyle(Palette.tint(for: metric.severity))
                            .contentTransition(.numericText(value: metric.fraction))
                    }
                    .lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .minimumScaleFactor(0.75)
        } else if let activity = summary.activity, summary.primary.id != "tokens" {
            HStack(spacing: 3) {
                Text("Today")
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(Format.tokens(activity.todayTokens)) tokens")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .font(.system(size: 11, weight: .semibold))
        } else {
            Text(" ")
                .font(.system(size: 11, weight: .semibold))
        }
    }
}

// MARK: Detail

private struct DetailPanel: View {
    var summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let meters = Array(summary.secondary.prefix(2))
            ForEach(Array(meters.enumerated()), id: \.element.id) { index, metric in
                MeterRow(metric: metric)
                    .padding(.top, index == 0 ? 0 : 11)
            }

            if meters.count < 2, let activity = summary.activity {
                ActivityChart(activity: activity)
                    .padding(.top, meters.isEmpty ? 0 : 12)
            } else if meters.isEmpty {
                StatusBlock(summary: summary)
            }

            Spacer(minLength: 0)

            bottomLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var bottomLine: some View {
        if let note = summary.note {
            Label(note, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
        } else if let activity = summary.activity, summary.secondary.count >= 2 {
            HStack(spacing: 4) {
                Text("Today")
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(Format.tokens(activity.todayTokens)) tokens")
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(activity.todayMessages) requests")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

private struct StatusBlock: View {
    var summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        if !summary.hasData { return "Say hi to Clawd" }
        switch summary.mood {
        case .sleeping where summary.primary.fraction >= 1: return "Limit reached"
        case .sleeping: return "All quiet"
        case .tired: return "Almost there"
        case .busy: return "Busy session"
        case .idle, .happy: return "Plenty left"
        }
    }

    private var message: String {
        if !summary.hasData { return "Open Clawdmeter once and your usage shows up here." }
        if summary.primary.fraction >= 1, let detail = summary.primary.detail {
            return "Clawd is napping. \(detail)."
        }
        return summary.primary.detail.map { "\($0)." } ?? "Your usage is up to date."
    }
}

private struct MeterRow: View {
    var metric: UsageSummary.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .foregroundStyle(.white)
                Spacer(minLength: 6)
                Text(metric.value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.tint(for: metric.severity))
                    .contentTransition(.numericText(value: metric.fraction))
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)

            UsageBar(fraction: metric.fraction, severity: metric.severity, height: 5)
                .padding(.top, 5)

            if let detail = metric.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: Pieces

struct PetTrack: View {
    var fraction: Double
    var severity: UsageLimit.Severity
    var mood: ClawdMood
    var unit: CGFloat = 2.5
    var barHeight: CGFloat = 6

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let fullColor = renderingMode == .fullColor
        GeometryReader { proxy in
            let petWidth = ClawdView.columns * unit
            let tip = proxy.size.width * min(max(fraction, 0), 1)
            let x = min(max(tip - petWidth / 2, 0), max(proxy.size.width - petWidth, 0))

            VStack(alignment: .leading, spacing: 0) {
                ClawdView(
                    mood: mood,
                    unit: unit,
                    color: fullColor ? Palette.clay : .white,
                    eyeColor: fullColor ? .black : .clear,
                    accessoriesOnLeft: x > proxy.size.width - petWidth * 1.6
                )
                .offset(x: x)
                .widgetAccentable()

                UsageBar(fraction: fraction, severity: severity, height: barHeight)
            }
        }
        .frame(height: ClawdView.rows * unit + barHeight)
    }
}

struct UsageBar: View {
    var fraction: Double
    var severity: UsageLimit.Severity
    var height: CGFloat = 6

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            let filled = clamped > 0 ? max(proxy.size.width * clamped, height) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.13))
                Capsule()
                    .fill(renderingMode == .fullColor ? AnyShapeStyle(Palette.fill(for: severity)) : AnyShapeStyle(.white))
                    .frame(width: filled)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

struct ActivityChart: View {
    var activity: Activity

    var body: some View {
        let days = Array(activity.days.suffix(7))
        let busiest = max(days.map(\.tokens).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .foregroundStyle(.white)
                Spacer(minLength: 6)
                Text("\(Format.tokens(days.map(\.tokens).reduce(0, +))) tokens")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isToday ? AnyShapeStyle(Palette.fill(for: .normal)) : AnyShapeStyle(.white.opacity(0.22)))
                            .frame(height: max(26 * CGFloat(day.tokens) / CGFloat(busiest), 3))
                            .frame(height: 26, alignment: .bottom)
                            .widgetAccentable(isToday)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(isToday ? 0.9 : 0.45))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
