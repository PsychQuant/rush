// Sources/CheTransportMCP/TDXClient.swift
import Foundation

struct TDXToken: Codable {
    let accessToken: String
    let expiresIn: Int
    let issuedAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case issuedAt
    }

    var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(expiresIn - 60)) // refresh 60s early
    }

    var isExpired: Bool { Date() >= expiresAt }
}

enum TDXError: Error, LocalizedError {
    case authFailed(String)
    case rateLimited
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "TDX auth failed: \(msg). Run: make setup-tdx"
        case .rateLimited: return "TDX rate limit exceeded; retry in 60s"
        case .http(let code, let msg): return "TDX HTTP \(code): \(msg)"
        case .decoding(let msg): return "TDX response format changed: \(msg). Please file an issue."
        case .network(let msg): return "Network error: \(msg). Check connection."
        }
    }
}

actor TDXClient {
    static let tokenEndpoint = URL(string: "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token")!
    static let apiBase = URL(string: "https://tdx.transportdata.tw/api/basic/")!

    private var cachedToken: TDXToken?

    static func parseTokenResponse(_ data: Data) throws -> TDXToken {
        struct Raw: Decodable {
            let access_token: String
            let expires_in: Int
        }
        do {
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            return TDXToken(accessToken: raw.access_token, expiresIn: raw.expires_in, issuedAt: Date())
        } catch {
            throw TDXError.decoding(error.localizedDescription)
        }
    }
}

extension TDXClient {
    static func cacheKey(path: String, queryItems: [URLQueryItem]) -> String {
        let sorted = queryItems.sorted { $0.name < $1.name }
        let qs = sorted.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return "\(path)?\(qs)"
    }
}

extension TDXClient {
    func ensureToken() async throws -> TDXToken {
        if let token = cachedToken, !token.isExpired { return token }

        let clientId = try Auth.read(account: "client_id")
        let clientSecret = try Auth.read(account: "client_secret")

        var req = URLRequest(url: Self.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var formComps = URLComponents()
        formComps.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]
        guard let bodyString = formComps.percentEncodedQuery else {
            throw TDXError.authFailed("Failed to encode credential form body")
        }
        req.httpBody = Data(bodyString.utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TDXError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TDXError.network("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TDXError.authFailed("HTTP \(http.statusCode)")
        }

        let token = try Self.parseTokenResponse(data)
        cachedToken = token
        return token
    }

    func fetch(path: String, queryItems: [URLQueryItem] = [], cacheTTL: TimeInterval, cache: Cache) async throws -> Data {
        let key = Self.cacheKey(path: path, queryItems: queryItems)

        if cacheTTL > 0, let cached = await cache.get(key: key) {
            return cached
        }

        // Build URL
        guard var comps = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw TDXError.network("Failed to construct URLComponents for path: \(path)")
        }
        var items = queryItems
        if !items.contains(where: { $0.name == "$format" }) {
            items.append(URLQueryItem(name: "$format", value: "JSON"))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            throw TDXError.network("Failed to construct request URL for path: \(path)")
        }

        let data = try await performRequest(url: url, attempt: 1)
        await cache.set(key: key, value: data, ttl: cacheTTL)
        return data
    }

    private func performRequest(url: URL, attempt: Int) async throws -> Data {
        let token = try await ensureToken()
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TDXError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TDXError.network("non-HTTP response")
        }

        if http.statusCode == 429 {
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                return try await performRequest(url: url, attempt: attempt + 1)
            }
            throw TDXError.rateLimited
        }
        if http.statusCode == 401 {
            cachedToken = nil
            throw TDXError.authFailed("HTTP 401")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TDXError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return data
    }
}
