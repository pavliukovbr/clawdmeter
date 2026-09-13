import ActivityKit
import SwiftUI
import WidgetKit

struct UsageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UsageActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Palette.backgroundBottom)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ClawdView(mood: state.mood, unit: 2.2)
                        .padding(.leading, 6)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Format.percent(state.percent))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.planName.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.clayLight)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetails(state: state)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                ClawdView(mood: state.mood, unit: 1.1)
                    .padding(.leading, 2)
            } compactTrailing: {
                Text(Format.percent(state.percent))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.tint(for: state.severity))
            } minimal: {
                ClawdView(mood: state.mood, unit: 0.9)
            }
            .keylineTint(Palette.clay)
        }
    }
}

private struct LockScreenActivityView: View {
    var state: UsageActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ClawdView(mood: state.mood, unit: 3)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.planName.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.clayLight)
                    Spacer()
                    Text(Format.percent(state.percent))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ActivityDetails(state: state)
            }
        }
        .padding(16)
    }
}

private struct ActivityDetails: View {
    var state: UsageActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageBar(fraction: state.percent / 100, severity: state.severity, height: 6, glints: true)
            HStack(spacing: 4) {
                Text(state.title)
                    .foregroundStyle(.white.opacity(0.9))
                if let resetsAt = state.resetsAt, resetsAt > Date() {
                    Text("resets in")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(timerInterval: Date()...resetsAt, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 4)
                if let weekly = state.weeklyPercent {
                    Text("Weekly \(Format.percent(weekly))")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
        }
    }
}
