import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import Network
import Security
import SystemConfiguration

/// Shares the usage summary with a paired iPhone over the local network or Tailscale.
/// Only paired phones can ask, and what they get back is encrypted.
@MainActor
final class PhoneSharing: ObservableObject {
    static let enabledKey = "shareWithiPhone"

    @Published private(set) var pairing: PhonePairing?
    @Published private(set) var lastSeen: Date?
    @Published private(set) var problem: String?

    private let store: UsageStore
    private let server = PhoneServer()
    private let pathMonitor = NWPathMonitor()
    private var secret: Data?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: UsageStore) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.enabledKey: false])

        server.onRequest = { [weak self] in
            MainActor.assumeIsolated { self?.lastSeen = Date() }
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &subscriptions)
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishReply() }
            .store(in: &subscriptions)

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.publishReply() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "clawdmeter.phone-path"))
        apply()
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Makes a new secret. Phones paired before stop getting answers until they pair again.
    func resetPairing() {
        let fresh = PhoneLink.newSecret()
        PairingSecret.save(fresh)
        secret = fresh
        server.update(secret: fresh)
        publishReply()
    }

    private func apply() {
        if isEnabled {
            guard !server.isRunning else { return }
            let current = PairingSecret.load() ?? {
                let fresh = PhoneLink.newSecret()
                PairingSecret.save(fresh)
                return fresh
            }()
            secret = current
            do {
                try server.start(port: PhoneLink.defaultPort, secret: current)
                problem = nil
            } catch {
                problem = "Port \(PhoneLink.defaultPort) is busy"
            }
            publishReply()
        } else if server.isRunning {
            server.stop()
            pairing = nil
        }
    }

    private func publishReply() {
        guard isEnabled, let secret else { return }
        let name = Host.current().localizedName ?? "Mac"
        let hosts = NetworkAddresses.current()
        let next = PhonePairing(name: name, hosts: hosts, port: PhoneLink.defaultPort, key: secret.base64URL)
        if next != pairing { pairing = next }
        server.update(reply: PhoneLinkReply(name: name, hosts: hosts, snapshot: store.snapshot))
    }
}

// MARK: Server

/// A tiny HTTP server that answers one signed request with one encrypted reply.
final class PhoneServer: @unchecked Sendable {
    var onRequest: (() -> Void)?

    private let queue = DispatchQueue(label: "clawdmeter.phone-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var secret = Data()
    private var reply = PhoneLinkReply(name: "", hosts: [], snapshot: nil)
    private var seenNonces: [String: Date] = [:]

    var isRunning: Bool {
        lock.withLock { listener != nil }
    }

    func start(port: UInt16, secret: Data) throws {
        stop()
        update(secret: secret)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        lock.withLock { self.listener = listener }
    }

    func stop() {
        lock.withLock {
            listener?.cancel()
            listener = nil
        }
    }

    func update(secret: Data) {
        lock.withLock {
            self.secret = secret
            seenNonces = [:]
        }
    }

    func update(reply: PhoneLinkReply) {
        lock.withLock { self.reply = reply }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let (status, body) = self.answer(buffer[..<end.lowerBound])
                let head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            } else if error != nil || isComplete || buffer.count > 8192 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func answer(_ head: Data) -> (String, Data) {
        guard let line = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n").first else {
            return ("400 Bad Request", Data())
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: String(parts[1])),
              components.path == PhoneLink.path else {
            return ("404 Not Found", Data())
        }
        let query = (components.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        guard let time = Int(query["t"] ?? ""), let nonce = query["n"], let signature = query["s"] else {
            return ("401 Unauthorized", Data())
        }

        return lock.withLock {
            let now = Date()
            seenNonces = seenNonces.filter { now.timeIntervalSince($0.value) < PhoneLink.clockTolerance * 2 }
            guard seenNonces[nonce] == nil,
                  PhoneLink.isValid(time: time, nonce: nonce, signature: signature, secret: secret, now: now) else {
                return ("401 Unauthorized", Data())
            }
            seenNonces[nonce] = now
            guard let plain = try? PhoneLink.encoder.encode(reply),
                  let sealed = try? PhoneLink.seal(plain, secret: secret) else {
                return ("500 Internal Server Error", Data())
            }
            let callback = onRequest
            DispatchQueue.main.async { callback?() }
            return ("200 OK", sealed)
        }
    }
}

// MARK: Helpers

/// The pairing secret stays in this Mac's keychain.
enum PairingSecret {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Clawdmeter iPhone Pairing",
        kSecAttrAccount as String: "secret",
    ]

    static func load() -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
        return data
    }

    static func save(_ secret: Data) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = secret
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

enum NetworkAddresses {
    /// The Bonjour name first, then the Wi-Fi address, then the Tailscale address if there is one.
    static func current() -> [String] {
        var hosts: [String] = []
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? {
            hosts.append("\(name).local")
        }

        var local: [String] = []
        var tailnet: [String] = []
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return hosts }
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

            if octets[0] == 100, (64...127).contains(octets[1]) {
                tailnet.append(text)
            } else if octets[0] != 169 {
                local.append(text)
            }
        }
        return hosts + local.prefix(1) + tailnet.prefix(1)
    }
}

enum QRCode {
    static func image(for text: String, side: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.samplingNearest() else { return nil }
        let scale = (side * 2 / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: scaled.extent.width / 2, height: scaled.extent.height / 2))
        image.addRepresentation(representation)
        return image
    }
}
