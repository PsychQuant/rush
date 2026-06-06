import XCTest
@testable import Rush

/// Live contract tests — one assertion per non-static TDX endpoint, driven by
/// enumerating `TDXEndpoints.allContractCases` (no separately maintained list).
///
/// Each endpoint is checked in three layers, in order:
///   1. HTTP status is not 404  (the path string is correct — this is what #4 broke)
///   2. HTTP status is 200      (the request is accepted)
///   3. the body decodes into the registry-declared model (schema still matches)
///
/// These are **opt-in and live**: they only run when `TDX_CONTRACT` is set AND
/// TDX credentials are available. Plain `swift test` skips the whole suite, so
/// the unit run stays offline and green. The CI workflow runs them on a nightly
/// schedule / release gate / manual dispatch — never on an ordinary PR.
final class ContractTests: XCTestCase {

    /// Endpoints the contract suite's first live run proved are broken by
    /// **pre-existing bugs beyond this change's #4 scope** (#4 covered rail
    /// station/timetable + traffic). They are quarantined — logged loudly every
    /// run but not failed — so the nightly keeps a green baseline that still
    /// catches NEW regressions in the other ~25 endpoints. Each entry names the
    /// fix; remove it when the underlying tool is fixed in follow-up. A
    /// quarantined endpoint that starts passing is reported so the entry can be
    /// deleted (it is never silently dropped).
    ///
    /// Follow-up tracked in PsychQuant/rush#4.
    // No endpoints are quarantined: every registered endpoint is expected to
    // pass live. (Maritime was removed — TDX no longer serves it on the unified
    // API and the legacy PTX Ship API is decommissioned.) The mechanism is kept
    // so a future drift can be quarantined transparently rather than silently skipped.
    static let knownPending: [String: String] = [:]

    /// Spacing between live requests to stay under TDX's per-minute rate limit
    /// (observed to trip on bursts well below the nominal 50/min). Overridable
    /// via `TDX_CONTRACT_DELAY_MS` for CI tuning.
    private var interRequestDelayNanoseconds: UInt64 {
        if let raw = ProcessInfo.processInfo.environment["TDX_CONTRACT_DELAY_MS"],
           let ms = UInt64(raw) {
            return ms * 1_000_000
        }
        return 2_000 * 1_000_000 // 2s default
    }

    /// Resolve TDX credentials, preferring environment variables
    /// (`TDX_CLIENT_ID` / `TDX_CLIENT_SECRET`) over the macOS keychain. CI
    /// runners have no keychain and inject the credentials as env vars from
    /// repo secrets; local dev falls back to the keychain entry written by
    /// `Rush --setup`.
    private static func resolveCredentials() throws -> (clientId: String, clientSecret: String) {
        let env = ProcessInfo.processInfo.environment
        if let id = env["TDX_CLIENT_ID"], let secret = env["TDX_CLIENT_SECRET"],
           !id.isEmpty, !secret.isEmpty {
            return (clientId: id, clientSecret: secret)
        }
        let id = try Auth.read(account: "client_id")
        let secret = try Auth.read(account: "client_secret")
        return (clientId: id, clientSecret: secret)
    }

    /// Skip (never fail) unless contract testing is explicitly enabled and
    /// credentials are resolvable.
    private func requireContractEnabled() throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Contract tests are opt-in. Set TDX_CONTRACT=1 to run live TDX checks.")
        }
        do {
            _ = try Self.resolveCredentials()
        } catch {
            throw XCTSkip("TDX credentials not available (env TDX_CLIENT_ID/SECRET or keychain). Run: make setup-tdx")
        }
    }

    func testAllRegisteredEndpoints() async throws {
        try requireContractEnabled()

        // One shared client so the OAuth token is fetched once, not per case.
        // Credentials come from env (CI) or keychain (local) — see resolveCredentials.
        let client = TDXClient(credentialProvider: { try Self.resolveCredentials() })
        let cache = Cache()

        // Report every failure rather than stopping at the first — a nightly run
        // should surface ALL drifted endpoints in one pass.
        continueAfterFailure = true

        let cases = TDXEndpoints.allContractCases
        var passed = 0
        var pending = 0
        for (index, c) in cases.enumerated() {
            let failure = await checkEndpoint(c, client: client, cache: cache)
            switch (failure, Self.knownPending[c.key]) {
            case (nil, nil):
                passed += 1
            case (nil, let reason?):
                // A quarantined endpoint now works — surface it so the entry is removed.
                passed += 1
                print("✅ [\(c.key)] now PASSES but is marked knownPending — remove it from knownPending. (was: \(reason))")
            case (let msg?, let reason?):
                // Pre-existing, documented breakage — log loudly, don't fail the suite.
                pending += 1
                print("⚠️ KNOWN-PENDING [\(c.key)]: \(reason)\n    observed: \(msg)")
            case (let msg?, nil):
                // A non-quarantined endpoint failed — this is the real signal.
                XCTFail(msg)
            }
            if index < cases.count - 1 {
                try await Task.sleep(nanoseconds: interRequestDelayNanoseconds)
            }
        }
        print("ContractTests: \(passed)/\(cases.count) passed, \(pending) known-pending (quarantined).")
    }

    /// Runs the three-layer check. Returns `nil` on success, or a human-readable
    /// failure message describing which layer failed.
    private func checkEndpoint(
        _ c: TDXEndpoints.ContractCase,
        client: TDXClient,
        cache: Cache
    ) async -> String? {
        do {
            // fetch() throws on any non-2xx, so reaching here means layers 1 & 2
            // (not-404, 200) both hold.
            let data = try await client.fetch(path: c.path, cacheTTL: 0, cache: cache)
            do {
                try c.decode(data) // layer 3: schema
                return nil
            } catch {
                return "[\(c.mode)/\(c.key)] schema drift — body did not decode for path '\(c.path)': \(error)"
            }
        } catch TDXError.http(let code, _) {
            if code == 404 {
                return "[\(c.mode)/\(c.key)] path drift — HTTP 404 for path '\(c.path)' (endpoint string is wrong)"
            }
            return "[\(c.mode)/\(c.key)] HTTP \(code) for path '\(c.path)' (request rejected, not a path-string issue)"
        } catch TDXError.rateLimited {
            return "[\(c.mode)/\(c.key)] rate limited for path '\(c.path)' — increase TDX_CONTRACT_DELAY_MS and rerun"
        } catch {
            return "[\(c.mode)/\(c.key)] request error for path '\(c.path)': \(error)"
        }
    }
}
