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

    static func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
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
