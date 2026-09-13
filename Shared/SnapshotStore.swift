import Foundation

/// The app writes the latest snapshot here and the widget reads it.
/// The widget sandbox has a read only exception for this folder.
enum SnapshotStore {
    static var directory: URL {
        URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Clawdmeter", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("usage.json") }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    /// Only percentages, reset times and daily totals are written, never tokens or account
    /// details, and the file is readable by the current user alone.
    static func save(_ snapshot: UsageSnapshot) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Inside a sandbox NSHomeDirectory points at the container, so ask the user database instead.
    static var realHomeDirectory: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
