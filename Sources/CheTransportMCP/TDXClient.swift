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
