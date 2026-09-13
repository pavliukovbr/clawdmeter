import SwiftUI

struct MenuPanel: View {
    @ObservedObject var store: UsageStore
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var pettedAt: Date?
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation) { context in
                UsageWidgetView(
                    layout: .medium,
                    snapshot: store.snapshot,
                    date: context.date,
                    petted: pettedAt.map { context.date.timeIntervalSince($0) < PetState.duration } ?? false
                )
                .environment(\.motionClock, context.date)
            }
            .frame(width: 364, height: 170)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
            .environment(\.colorScheme, .dark)
            .onTapGesture {
                withAnimation(.spring(duration: 0.4)) { pettedAt = Date() }
                store.refreshSoon()
            }

            HStack(spacing: 8) {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    store.refreshSoon(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
                .disabled(store.isRefreshing)
            }
            .padding(.horizontal, 4)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: opensAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }
                    .padding(.vertical, 4)

                MenuRow(title: "Hide Menu Bar Icon") {
                    showMenuBarIcon = false
                }
                .help("Open Clawdmeter again to bring the icon back")

                MenuRow(title: "Quit Clawdmeter") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 392)
        .onAppear {
            opensAtLogin = LoginItem.isEnabled
            store.refreshSoon()
        }
    }

    private var status: String {
        guard let snapshot = store.snapshot else { return "Looking for your Claude sign in" }
        switch snapshot.status {
        case .signedOut:
            return "Sign in to Claude Code to see your limits"
        case .expired:
            return "Open Claude Code to reconnect"
        case .offline:
            return "Offline, showing numbers from \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
        case .ok:
            return "\(snapshot.plan.name) plan, updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}

private struct MenuRow: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
    }
}
