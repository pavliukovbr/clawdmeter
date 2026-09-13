import AppKit
import CryptoKit
import Security

/// Installs new versions from the GitHub releases of this project. It only reads the public
/// release list and downloads the files; nothing about you or your Mac is sent.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        var version: String
        var archive: URL
        var checksum: URL?
        var page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        case failed(String)
    }

    static let autoCheckKey = "checkForUpdatesAutomatically"
    private static let repository = "pavliukovbr/clawdmeter"
    private static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var state: State = .idle
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    init() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer?.tolerance = 600
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        Task { await check(manually: false) }
    }

    func check(manually: Bool) async {
        if case .installing = state { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        do {
            guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Clawdmeter", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.unreachable }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let latest = try decoder.decode(GitHubRelease.self, from: data)
            let version = latest.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            guard Self.isVersion(version, newerThan: currentVersion),
                  let archive = latest.assets.first(where: { $0.name == "Clawdmeter.zip" }) else {
                state = manually ? .upToDate : .idle
                return
            }
            state = .available(Release(
                version: version,
                archive: archive.browserDownloadUrl,
                checksum: latest.assets.first(where: { $0.name == "Clawdmeter.zip.sha256" })?.browserDownloadUrl,
                page: latest.htmlUrl
            ))
        } catch {
            state = manually ? .failed("Could not reach GitHub") : .idle
        }
    }

    func install(_ release: Release) async {
        state = .installing(release)
        do {
            let workspace = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClawdmeterUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

            let (download, _) = try await URLSession.shared.download(from: release.archive)
            let archive = workspace.appendingPathComponent("Clawdmeter.zip")
            try FileManager.default.moveItem(at: download, to: archive)

            if let checksumURL = release.checksum {
                let (checksumData, _) = try await URLSession.shared.data(from: checksumURL)
                let expected = String(decoding: checksumData, as: UTF8.self)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { $0.lowercased() }
                let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
                guard expected == actual else { throw UpdateError.damaged }
            }

            try run("/usr/bin/ditto", ["-x", "-k", archive.path, workspace.path])
            let newApp = workspace.appendingPathComponent("Clawdmeter.app")
            guard let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  bundle.infoDictionary?["CFBundleShortVersionString"] as? String == release.version,
                  Self.hasValidSignature(newApp) else { throw UpdateError.damaged }

            try replaceAndRelaunch(with: newApp)
        } catch UpdateError.notWritable {
            state = .failed("Move Clawdmeter to Applications to update")
        } catch {
            state = .failed("The update could not be installed")
        }
    }

    // MARK: Private

    private func replaceAndRelaunch(with newApp: URL) throws {
        let manager = FileManager.default
        let current = Bundle.main.bundleURL
        guard manager.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError.notWritable
        }

        // Swap the bundles, and put the old one back if anything goes wrong.
        let previous = newApp.deletingLastPathComponent().appendingPathComponent("Previous.app")
        try manager.moveItem(at: current, to: previous)
        do {
            try manager.moveItem(at: newApp, to: current)
        } catch {
            try? manager.moveItem(at: previous, to: current)
            throw error
        }

        // Let Launch Services and WidgetKit see the new widget right away.
        try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", current.path])

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.damaged }
    }

    private static func hasValidSignature(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

private enum UpdateError: Error {
    case unreachable, damaged, notWritable
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browserDownloadUrl: URL
    }

    var tagName: String
    var htmlUrl: URL
    var assets: [Asset]
}
