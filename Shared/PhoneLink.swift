import CryptoKit
import Foundation

/// What an iPhone needs to reach a Mac. It travels once, inside the pairing QR code.
struct PhonePairing: Codable, Equatable {
    var name: String
    var hosts: [String]
    var port: UInt16
    var key: String

    var url: URL? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        var components = URLComponents()
        components.scheme = "clawdmeter"
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "d", value: data.base64URL)]
        return components.url
    }

    init(name: String, hosts: [String], port: UInt16, key: String) {
        self.name = name
        self.hosts = hosts
        self.port = port
        self.key = key
    }

    init?(url: URL) {
        guard url.scheme == "clawdmeter", url.host == "pair",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "d" })?.value,
              let data = Data(base64URL: value),
              let pairing = try? JSONDecoder().decode(PhonePairing.self, from: data),
              Data(base64URL: pairing.key)?.count == 32,
              !pairing.hosts.isEmpty else { return nil }
        self = pairing
    }
}

/// The Mac's answer. It is encrypted before it leaves the Mac.
struct PhoneLinkReply: Codable, Equatable {
    var name: String
    var hosts: [String]
    var snapshot: UsageSnapshot?
    var lastFinishedTurn: FinishedTurn?
}

/// When Claude last finished answering, how long it worked and in which project folder.
struct FinishedTurn: Codable, Equatable {
    var date: Date
    var duration: TimeInterval?
    var project: String?
}

/// Requests are signed and replies are encrypted with keys made from the pairing secret, so
/// nothing readable crosses the network, even as plain HTTP over Wi-Fi.
enum PhoneLink {
    static let defaultPort: UInt16 = 47_847
    static let path = "/v1/usage"
    static let clockTolerance: TimeInterval = 120

    static func newSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    static func requestURL(host: String, port: UInt16, secret: Data, now: Date = Date()) -> URL? {
        let time = Int(now.timeIntervalSince1970)
        let nonce = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.base64URL
        let signature = HMAC<SHA256>.authenticationCode(for: message(time: time, nonce: nonce), using: key(secret, "auth"))

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "t", value: String(time)),
            URLQueryItem(name: "n", value: nonce),
            URLQueryItem(name: "s", value: Data(signature).base64URL),
        ]
        return components.url
    }

    static func isValid(time: Int, nonce: String, signature: String, secret: Data, now: Date = Date()) -> Bool {
        guard abs(now.timeIntervalSince1970 - Double(time)) <= clockTolerance,
              nonce.count <= 64,
              let code = Data(base64URL: signature) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: message(time: time, nonce: nonce), using: key(secret, "auth"))
    }

    static func seal(_ data: Data, secret: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key(secret, "seal")).combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return combined
    }

    static func open(_ data: Data, secret: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(secret, "seal"))
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func message(time: Int, nonce: String) -> Data {
        Data("GET \(path) \(time) \(nonce)".utf8)
    }

    private static func key(_ secret: Data, _ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            info: Data("clawdmeter \(purpose)".utf8),
            outputByteCount: 32
        )
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL text: String) {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
