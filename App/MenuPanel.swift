import SwiftUI

struct MenuPanel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var oldPhoneScreen: OldPhoneScreen

    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var pettedAt: Date?
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(NotchPetController.enabledKey) private var notchPetEnabled = true
    @AppStorage(KeepAwake.modeKey) private var keepAwakeMode = KeepAwake.Mode.off.rawValue
    @AppStorage(KeepAwake.displayKey) private var keepDisplayAwake = false
    @AppStorage(Updater.autoCheckKey) private var checksAutomatically = true
    @AppStorage(OldPhoneScreen.enabledKey) private var showsOnOldPhone = false
    @AppStorage(RoamingController.enabledKey) private var walksAround = true
    @AppStorage(ClaudeNotifier.enabledKey) private var notifiesWhenDone = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview

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

            updateBanner

            VStack(spacing: 0) {
                SettingRow(symbol: "sparkles", tint: Palette.clay, title: "Clawd in the Notch") {
                    Toggle("", isOn: $notchPetEnabled).labelsHidden()
                }
                SettingRow(symbol: "figure.walk", tint: .orange, title: "Clawd Walks Around") {
                    Toggle("", isOn: $walksAround).labelsHidden()
                }
                SettingRow(symbol: "bell.badge.fill", tint: .red, title: "Notify When Claude Finishes") {
                    Toggle("", isOn: $notifiesWhenDone).labelsHidden()
                }
                SettingRow(symbol: "cup.and.saucer.fill", tint: .brown, title: "Keep Mac Awake", detail: keepAwake.isActive ? "Active now" : nil) {
                    Picker("", selection: $keepAwakeMode) {
                        ForEach(KeepAwake.Mode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if keepAwakeMode != KeepAwake.Mode.off.rawValue {
                    SettingRow(symbol: "display", tint: .indigo, title: "Keep Display On") {
                        Toggle("", isOn: $keepDisplayAwake).labelsHidden()
                    }
                }
                SettingRow(symbol: "iphone.gen1", tint: .teal, title: "Screen on an Old Phone", detail: oldPhoneDetail) {
                    Toggle("", isOn: $showsOnOldPhone).labelsHidden()
                }
                if showsOnOldPhone, let address = oldPhoneScreen.address {
                    OldPhoneCard(address: address)
                }
                SettingRow(symbol: "power", tint: .green, title: "Open at Login") {
                    Toggle("", isOn: $opensAtLogin)
                        .labelsHidden()
                        .onChange(of: opensAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
                }
                SettingRow(symbol: "arrow.down.circle.fill", tint: .blue, title: "Update Automatically") {
                    Toggle("", isOn: $checksAutomatically).labelsHidden()
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                MenuRow(title: "Check for Updates") {
                    Task { await updater.check(manually: true) }
                }
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
            oldPhoneScreen.refreshAddress()
            store.refreshSoon()
        }
    }

    private var preview: some View {
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
    }

    @ViewBuilder
    private var updateBanner: some View {
        switch updater.state {
        case .available(let release):
            banner(symbol: "arrow.down.circle.fill", text: "Clawdmeter \(release.version) is available") {
                Button("Update") { Task { await updater.install(release) } }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        case .installing(let release):
            banner(symbol: "arrow.down.circle.fill", text: "Installing \(release.version)") {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            banner(symbol: "checkmark.circle.fill", text: "Clawdmeter \(updater.currentVersion) is up to date") { EmptyView() }
        case .failed(let message):
            banner(symbol: "exclamationmark.triangle.fill", text: message) {
                Button("Try Again") { Task { await updater.check(manually: true) } }
                    .controlSize(.small)
            }
        case .idle, .checking:
            EmptyView()
        }
    }

    private func banner(symbol: String, text: String, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.clay)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var oldPhoneDetail: String? {
        guard showsOnOldPhone else { return nil }
        if let problem = oldPhoneScreen.problem { return problem }
        return oldPhoneScreen.address == nil ? "Connect this Mac to Wi-Fi" : nil
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

private struct SettingRow<Accessory: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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

private struct OldPhoneCard: View {
    var address: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = QRCode.image(for: address, side: 112) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .padding(6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Scan with the Old Phone")
                    .font(.system(size: 12, weight: .semibold))
                Text("Scan it in Clawdmeter on the phone, or open the address in any browser on the same Wi-Fi.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(address)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
