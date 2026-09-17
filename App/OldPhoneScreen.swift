import AppKit
import Combine
import CryptoKit
import Network
import SystemConfiguration

/// Turns an old phone into a little usage screen. The Mac answers a page on the home
/// network, the phone keeps it open, and nothing leaves the network. Off until you turn
/// it on, and every request needs the key from the address.
@MainActor
final class OldPhoneScreen: ObservableObject {
    static let enabledKey = "screenOnOldPhone"
    static let port: UInt16 = 47_848

    /// The address to open on the phone, or nil while the screen is off.
    @Published private(set) var address: String?
    @Published private(set) var problem: String?

    private let store: UsageStore
    private let watcher: ClaudeActivityWatcher
    private let server = OldPhoneServer()
    private let pathMonitor = NWPathMonitor()
    private var key: String?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: UsageStore, watcher: ClaudeActivityWatcher) {
        self.store = store
        self.watcher = watcher
        UserDefaults.standard.register(defaults: [Self.enabledKey: false])

        server.usage = { [weak self] in self?.usage() }
        server.onFailure = { [weak self] in
            MainActor.assumeIsolated {
                self?.problem = "Port \(Self.port) is busy"
                self?.refreshAddress()
            }
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &subscriptions)

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshAddress() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "clawdmeter.old-phone-path"))
        apply()
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// The Wi-Fi address can change without the network path changing, so the menu asks again.
    func refreshAddress() {
        var next: String?
        if isEnabled, server.isRunning, let key, let host = NetworkAddresses.homeAddress() {
            next = "http://\(host):\(Self.port)/?k=\(key)"
        }
        if next != address { address = next }
    }

    private func apply() {
        if isEnabled {
            guard !server.isRunning else { return }
            guard let key = key ?? OldPhoneKey.loadOrCreate() else {
                problem = "Could not read the key from the keychain"
                return
            }
            self.key = key
            do {
                try server.start(port: Self.port, key: key)
                problem = nil
            } catch {
                problem = "Port \(Self.port) is busy"
            }
            refreshAddress()
        } else if server.isRunning {
            server.stop()
            refreshAddress()
        }
    }

    /// What the phone draws: the numbers, not the logs behind them.
    private func usage() -> Data? {
        let now = Date()
        let summary = UsageSummary(snapshot: store.snapshot, date: now)
        let working = watcher.isClaudeWorking(within: 45, now: now)
        let turn = watcher.lastFinishedTurn
        // Claude has stopped and the turn is fresh, so it is your move.
        let asking = !working && turn.map { now.timeIntervalSince($0.date) < 10 * 60 } == true
        let resetSeconds = store.snapshot?.session?.resetsAt.map { max(Int($0.timeIntervalSince(now)), 0) } ?? 0

        let payload: [String: Any] = [
            "plan": summary.planName,
            "title": summary.primary.title,
            "value": summary.primary.value,
            "fraction": Self.fraction(summary.primary.fraction),
            "severity": summary.primary.severity.rawValue,
            "detail": Self.orNull(summary.primary.detail),
            "note": Self.orNull(summary.note),
            "mood": summary.mood.rawValue,
            "working": working,
            "activity": (watcher.latest?.activity ?? .idle).rawValue,
            "asking": asking,
            "turnId": Self.orNull(turn.map { Int($0.date.timeIntervalSince1970) }),
            "turnText": Self.orNull(turn.map(Format.finished)),
            "resetSeconds": resetSeconds,
            "today": Self.orNull(summary.activity.map { Format.tokens($0.todayTokens) }),
            "requests": summary.activity?.todayMessages ?? 0,
            "second": Self.orNull(summary.secondary.first.map { metric in
                [
                    "title": metric.title,
                    "value": metric.value,
                    "fraction": Self.fraction(metric.fraction),
                    "severity": metric.severity.rawValue,
                ] as [String: Any]
            }),
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Four decimals written as they read, 0.6234 rather than 0.62339999999999995.
    private static func fraction(_ value: Double) -> Decimal {
        guard value.isFinite else { return 0 }
        return Decimal(Int((min(max(value, 0), 1) * 10_000).rounded())) / 10_000
    }

    private static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}

// MARK: Server

/// Plain HTTP, so a browser from 2011 can read it. The key in the address is the only lock,
/// which is why nothing outside the home network gets an answer.
final class OldPhoneServer: @unchecked Sendable {
    /// Built on the main thread for every request, so the numbers are never stale.
    var usage: (@MainActor () -> Data?)?
    var onFailure: (() -> Void)?

    private static let requestLimit = 4096
    private let queue = DispatchQueue(label: "clawdmeter.old-phone-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var key = ""

    var isRunning: Bool {
        lock.withLock { listener != nil }
    }

    func start(port: UInt16, key: String) throws {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard case .failed = state, let self, let listener else { return }
            listener.cancel()
            self.lock.withLock {
                if self.listener === listener { self.listener = nil }
            }
            let callback = self.onFailure
            DispatchQueue.main.async { callback?() }
        }
        lock.withLock {
            self.key = key
            self.listener = listener
        }
        listener.start(queue: queue)
    }

    func stop() {
        lock.withLock {
            listener?.cancel()
            listener = nil
        }
    }

    private func serve(_ connection: NWConnection) {
        guard Self.isHomeNetwork(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.requestLimit) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.answer(buffer[..<end.lowerBound], on: connection)
            } else if error != nil || isComplete || buffer.count >= Self.requestLimit {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func answer(_ head: Data, on connection: NWConnection) {
        let line = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let target = parts[1]
        let path = target.prefix { $0 != "?" }
        let query = target.drop { $0 != "?" }.dropFirst()

        guard parts[0] == "GET" else {
            Self.send(405, "text/plain", Data("Only GET is served here.".utf8), on: connection)
            return
        }
        guard matches(query) else {
            Self.send(401, "text/plain", Data("The key in the address does not match.".utf8), on: connection)
            return
        }

        switch path {
        case "/", "/index.html":
            Self.send(200, "text/html; charset=utf-8", Data(OldPhonePage.html.utf8), on: connection)
        case "/usage":
            DispatchQueue.main.async { [weak self] in
                let body = MainActor.assumeIsolated { self?.usage?() }
                if let body {
                    Self.send(200, "application/json; charset=utf-8", body, on: connection)
                } else {
                    Self.send(500, "text/plain", Data("Try again in a moment.".utf8), on: connection)
                }
            }
        default:
            Self.send(404, "text/plain", Data("Nothing here.".utf8), on: connection)
        }
    }

    private static func send(_ status: Int, _ type: String, _ body: Data, on connection: NWConnection) {
        let reason = switch status {
        case 200: "OK"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Internal Server Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Looks at every byte whatever it finds, so timing says nothing about the key.
    private func matches(_ query: Substring) -> Bool {
        let expected = Array(lock.withLock { key }.utf8)
        guard !expected.isEmpty else { return false }
        for pair in query.split(separator: "&") {
            guard let mark = pair.firstIndex(of: "="), pair[..<mark] == "k" else { continue }
            let raw = String(pair[pair.index(after: mark)...])
            let given = Array((raw.removingPercentEncoding ?? raw).utf8)
            guard given.count == expected.count else { return false }
            return zip(given, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
        }
        return false
    }

    /// Only phones on the same home network are answered.
    private static func isHomeNetwork(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return isHomeNetwork(address)
        case .ipv6(let address):
            if address.isIPv4Mapped, let mapped = address.asIPv4 { return isHomeNetwork(mapped) }
            return address.isLoopback || address.isLinkLocal || address.isUniqueLocal
        default:
            return false
        }
    }

    private static func isHomeNetwork(_ address: IPv4Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        switch bytes[0] {
        case 10, 127: return true
        case 169: return bytes[1] == 254
        case 172: return (16...31).contains(bytes[1])
        case 192: return bytes[1] == 168
        default: return false
        }
    }
}

// MARK: Helpers

/// The key stays in this Mac's keychain. The security tool writes and reads it, so a newer
/// build of the app can still read it without a keychain prompt.
enum OldPhoneKey {
    private static let service = "Clawdmeter Old Phone Screen"
    private static let account = "key"
    private static let itemNotFound: Int32 = 44

    static func loadOrCreate() -> String? {
        let found = security(["find-generic-password", "-s", service, "-a", account, "-w"])
        if found.status == 0, !found.output.isEmpty { return found.output }
        // Only make a new key when there is none, not when the keychain is locked.
        guard found.status == itemNotFound else { return nil }

        let fresh = SymmetricKey(size: SymmetricKeySize(bitCount: 64)).withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
        let saved = security(["add-generic-password", "-s", service, "-a", account, "-w", fresh])
        return saved.status == 0 ? fresh : nil
    }

    private static func security(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension NetworkAddresses {
    /// The address a phone on the same Wi-Fi can reach. Wi-Fi and Ethernet win over VPNs
    /// and virtual machine bridges, which also use private addresses.
    static func homeAddress() -> String? {
        var found: [(name: String, address: String)] = []
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let socket = entry.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET),
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0,
                  (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

            var address = socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let text = String(cString: buffer)
            let octets = text.split(separator: ".").compactMap { Int($0) }
            guard octets.count == 4 else { continue }

            if octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168) {
                found.append((String(cString: entry.ifa_name), text))
            }
        }

        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        let physical = found.filter { $0.name.hasPrefix("en") }
        return (physical.first { $0.name == primary } ?? physical.first ?? found.first)?.address
    }
}
