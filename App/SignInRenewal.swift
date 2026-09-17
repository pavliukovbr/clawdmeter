import Foundation

/// The Claude desktop app keeps a sign in of its own, so the one Claude Code leaves in the
/// keychain runs out when the command line has not been used for a few hours. Starting the
/// command line with a local command that never reaches the model is enough for it to renew
/// that sign in by itself. Nothing is sent to Claude and no usage is spent.
enum SignInRenewal {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastAttempt = Date.distantPast
    private static let minimumGap: TimeInterval = 10 * 60
    private static let timeout: TimeInterval = 45

    /// True when the command line ran, which is the moment to read the keychain again.
    static func renew() async -> Bool {
        let now = Date()
        let allowed = lock.withLock {
            guard now.timeIntervalSince(lastAttempt) > minimumGap else { return false }
            lastAttempt = now
            return true
        }
        guard allowed, let command = commandLine() else { return false }
        return await Task.detached(priority: .utility) { run(command) }.value
    }

    private static func run(_ command: URL) -> Bool {
        let process = Process()
        process.executableURL = command
        process.arguments = ["-p", "/status", "--no-session-persistence"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        if process.isRunning { process.terminate() }
        return true
    }

    /// Apps opened from the Dock do not get the shell's PATH, so look where the installers put it.
    private static func commandLine() -> URL? {
        let home = SnapshotStore.realHomeDirectory
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
