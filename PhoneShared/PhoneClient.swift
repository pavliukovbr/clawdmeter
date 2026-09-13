import Foundation

enum PhoneClientError: Error {
    case notPaired
    case rejected
    case unreachable
}

enum PhoneClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Asks every address of the Mac at once and keeps the first good answer, so the Wi-Fi
    /// address wins at home and the Tailscale one wins everywhere else.
    static func fetch(_ pairing: PhonePairing) async throws -> (reply: PhoneLinkReply, host: String) {
        guard let secret = Data(base64URL: pairing.key) else { throw PhoneClientError.notPaired }

        return try await withThrowingTaskGroup(of: (PhoneLinkReply, String)?.self) { group in
            for host in pairing.hosts {
                group.addTask {
                    guard let url = PhoneLink.requestURL(host: host, port: pairing.port, secret: secret) else { return nil }
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401 { throw PhoneClientError.rejected }
                    guard status == 200 else { return nil }
                    let reply = try PhoneLink.decoder.decode(PhoneLinkReply.self, from: PhoneLink.open(data, secret: secret))
                    return (reply, host)
                }
            }

            var rejected = false
            while let result = await group.nextResult() {
                switch result {
                case .success(let answer?):
                    group.cancelAll()
                    return answer
                case .failure(PhoneClientError.rejected):
                    rejected = true
                default:
                    break
                }
            }
            throw rejected ? PhoneClientError.rejected : PhoneClientError.unreachable
        }
    }
}

enum UsageRefresher {
    struct Result {
        var stored: PhoneVault.StoredReply?
        var error: PhoneClientError?
    }

    /// Fetches from the Mac and remembers the answer. When the Mac cannot be reached, the
    /// last answer comes back with the error.
    static func refresh() async -> Result {
        guard var pairing = PhoneVault.pairing else {
            return Result(stored: nil, error: .notPaired)
        }
        do {
            let (reply, host) = try await PhoneClient.fetch(pairing)
            let stored = PhoneVault.StoredReply(reply: reply, receivedAt: Date(), host: host)
            PhoneVault.lastReply = stored

            // Learn new addresses, like the Tailscale one once it is turned on.
            let hosts = Array((reply.hosts + pairing.hosts.filter { !reply.hosts.contains($0) }).prefix(5))
            if hosts != pairing.hosts || reply.name != pairing.name {
                pairing.hosts = hosts
                pairing.name = reply.name
                PhoneVault.pairing = pairing
            }
            return Result(stored: stored, error: nil)
        } catch {
            return Result(stored: PhoneVault.lastReply, error: error as? PhoneClientError ?? .unreachable)
        }
    }
}
