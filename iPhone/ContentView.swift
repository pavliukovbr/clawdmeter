import SwiftUI

struct ContentView: View {
    @ObservedObject var model: PhoneModel

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if model.pairing == nil {
                PairingView(model: model)
            } else {
                UsageScreen(model: model)
            }
        }
        .overlay(alignment: .top) {
            if let turn = model.finishedBanner {
                FinishedBanner(turn: turn)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.3)) { model.finishedBanner = nil }
                    }
            }
        }
        .preferredColorScheme(.dark)
        .alert("That is not a Clawdmeter link", isPresented: $model.pairingFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Scan the code shown under Share with iPhone in the Clawdmeter menu on your Mac.")
        }
    }
}

// MARK: Claude finished

private struct FinishedBanner: View {
    var turn: FinishedTurn

    var body: some View {
        HStack(spacing: 14) {
            TimelineView(.animation) { context in
                ClawdView(mood: .happy, unit: 2.2)
                    .environment(\.motionClock, context.date)
            }
            .frame(width: 36, height: 22)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude finished")
                    .font(.headline)
                Text(Format.finished(turn))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

// MARK: Paired

private struct UsageScreen: View {
    @ObservedObject var model: PhoneModel
    @State private var pettedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                TimelineView(.animation) { context in
                    UsageWidgetView(
                        layout: .medium,
                        snapshot: model.snapshot,
                        date: context.date,
                        petted: pettedAt.map { context.date.timeIntervalSince($0) < PetState.duration } ?? false
                    )
                    .environment(\.motionClock, context.date)
                }
                .frame(width: 364, height: 170)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.1))
                }
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    withAnimation(.spring(duration: 0.4)) { pettedAt = Date() }
                    Task { await model.refresh() }
                }

                ConnectionRow(model: model)

                VStack(spacing: 0) {
                    Toggle(isOn: $model.showsInDynamicIsland) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clawd in the Dynamic Island")
                            Text("Follows your session on the Lock Screen too. iOS ends it after 8 hours.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Palette.clay)
                    .padding(16)
                }
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                tips
            }
            .padding(20)
        }
        .refreshable { await model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clawdmeter")
                    .font(.largeTitle.bold())
                if let name = model.pairing?.name {
                    Text("Paired with \(name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                Button("Paste Pairing Link", systemImage: "doc.on.clipboard") {
                    model.pasteLink()
                }
                Button("Unpair", systemImage: "xmark.circle", role: .destructive) {
                    model.unpair()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(Palette.clayLight)
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Clawd to your iPhone")
                .font(.headline)
            TipRow(symbol: "square.grid.2x2", text: "Touch and hold the Home Screen, tap Edit, then Add Widget.")
            TipRow(symbol: "lock", text: "Touch and hold the Lock Screen and tap Customize for the ring and bar.")
            TipRow(symbol: "powersleep", text: "Charge the iPhone on its side for a big Clawd in StandBy.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ConnectionRow: View {
    @ObservedObject var model: PhoneModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var color: Color {
        switch model.connection {
        case .connected: .green
        case .connecting: Palette.amber
        case .unreachable, .rejected, .notPaired: Palette.red
        }
    }

    private var text: String {
        switch model.connection {
        case .connected:
            return model.stored?.viaTailscale == true ? "Connected through Tailscale" : "Connected on this network"
        case .connecting:
            return "Looking for your Mac"
        case .rejected:
            return "Your Mac reset its pairing. Scan the new code."
        case .unreachable:
            if let received = model.stored?.receivedAt {
                return "Mac not reachable. Showing numbers from \(received.formatted(date: .omitted, time: .shortened))."
            }
            return "Mac not reachable. Join the same Wi-Fi or turn on Tailscale."
        case .notPaired:
            return "Not paired"
        }
    }
}

private struct TipRow: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.clayLight)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Not paired

private struct PairingView: View {
    @ObservedObject var model: PhoneModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            TimelineView(.animation) { context in
                ClawdView(mood: .happy, unit: 7)
                    .environment(\.motionClock, context.date)
            }
            .frame(height: 90)

            VStack(spacing: 8) {
                Text("Pair with your Mac")
                    .font(.title.bold())
                Text("Clawdmeter on your Mac reads your Claude usage and shares it with this iPhone. Your sign in never leaves the Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: "On your Mac, open Clawdmeter in the menu bar and turn on Share with iPhone.")
                StepRow(number: 2, text: "Scan the code with the Camera app and open the link.")
                StepRow(number: 3, text: "Away from home? Install Tailscale on both and sign in with the same account.")
            }
            .padding(18)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()

            Button {
                model.pasteLink()
            } label: {
                Text("Paste Pairing Link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.clay)
        }
        .padding(24)
    }
}

private struct StepRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Palette.clayLight, in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}
