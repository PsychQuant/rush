import XCTest
@testable import Rush

/// HTTP-layer tests for `TDXClient` using a stubbed `URLSession` (via
/// `MockURLProtocol`). These cover the parts that the existing unit tests
/// could not reach: OAuth round-trip, token caching, 429 retry-once-then-fail,
/// 401 token invalidation, $format=JSON auto-append, and Cache integration.
///
/// All tests inject a custom session, a constant credential provider (no
/// keychain access), and a 0-ns retry delay (so the 429 retry test runs
/// instantly).
final class TDXClientHTTPTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        MockURLProtocol.stub = MockURLProtocol.Stub()
    }

    override func tearDown() {
        MockURLProtocol.stub = nil
        super.tearDown()
    }

    // MARK: - ensureToken

    func testEnsureTokenFetchesAndCaches() async throws {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON()))
        ]
        let client = Self.makeClient()

        let token1 = try await client.ensureToken()
        XCTAssertEqual(token1.accessToken, "test-access-token")

        // Second call must NOT issue another HTTP request — token is cached.
        let token2 = try await client.ensureToken()
        XCTAssertEqual(token2.accessToken, "test-access-token")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 1,
                       "ensureToken() should reuse cached token, not re-hit OAuth")
    }

    func testEnsureTokenFailsOnHTTP4xx() async {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(401), Data(#"{"error":"invalid_client"}"#.utf8)))
        ]
        let client = Self.makeClient()

        do {
            _ = try await client.ensureToken()
            XCTFail("expected authFailed")
        } catch let TDXError.authFailed(msg) {
            XCTAssertTrue(msg.contains("401"), "error message should expose HTTP status; got \(msg)")
        } catch {
            XCTFail("expected TDXError.authFailed, got \(error)")
        }
    }

    func testEnsureTokenSurfacesCredentialProviderError() async {
        struct KeychainEmpty: Error {}
        let client = TDXClient(
            session: Self.makeSession(),
            credentialProvider: { throw KeychainEmpty() },
            retryDelayNanoseconds: 0
        )

        do {
            _ = try await client.ensureToken()
            XCTFail("expected throw")
        } catch is KeychainEmpty {
            // expected
        } catch {
            XCTFail("expected KeychainEmpty, got \(error)")
        }
    }

    // MARK: - fetch happy path

    func testFetchSucceedsAndReturnsData() async throws {
        let payload = Data(#"{"matches":[]}"#.utf8)
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), payload))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        let data = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)
        XCTAssertEqual(data, payload)
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 2,
                       "first call hits OAuth, second hits the API")
    }

    func testFetchAutoAppendsFormatJSON() async throws {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), Data("[]".utf8)))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        _ = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)
        let apiCall = MockURLProtocol.stub?.calls.last
        let queryString = apiCall?.url?.query ?? ""
        XCTAssertTrue(queryString.contains("$format=JSON"),
                      "fetch should auto-append $format=JSON; got query \(queryString)")
    }

    func testFetchPreservesExistingFormatParam() async throws {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), Data("[]".utf8)))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        _ = try await client.fetch(
            path: "v3/Rail/TRA/Station",
            queryItems: [URLQueryItem(name: "$format", value: "XML")],
            cacheTTL: 0, cache: cache
        )
        let apiCall = MockURLProtocol.stub?.calls.last
        let queryString = apiCall?.url?.query ?? ""
        XCTAssertTrue(queryString.contains("$format=XML"),
                      "caller-supplied $format should not be overridden; got \(queryString)")
        // And NOT appended twice
        let occurrences = queryString.components(separatedBy: "$format=").count - 1
        XCTAssertEqual(occurrences, 1, "exactly one $format param expected")
    }

    // MARK: - 429 retry

    func testFetch429RetriesOnceThenSucceeds() async throws {
        let payload = Data(#"{"ok":true}"#.utf8)
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(429), Data())),
            .success((MockURLProtocol.httpResponse(200), payload))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        let data = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)
        XCTAssertEqual(data, payload)
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 3,
                       "expected OAuth + 429 + retry = 3 calls")
    }

    func testFetch429TwiceFailsRateLimited() async {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(429), Data())),
            .success((MockURLProtocol.httpResponse(429), Data()))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        do {
            _ = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)
            XCTFail("expected rateLimited")
        } catch TDXError.rateLimited {
            // expected
        } catch {
            XCTFail("expected TDXError.rateLimited, got \(error)")
        }
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 3,
                       "expected OAuth + 429 + 429 = 3 calls (no second retry)")
    }

    // MARK: - 401 token invalidation

    func testFetch401InvalidatesCachedToken() async throws {
        // Sequence: OAuth → API (401) → throws. Then a fresh fetch must
        // trigger a NEW OAuth round-trip (cachedToken cleared by the 401).
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(401), Data())),
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), Data("[]".utf8)))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        do {
            _ = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)
            XCTFail("expected authFailed on 401")
        } catch TDXError.authFailed {
            // expected
        } catch {
            XCTFail("expected authFailed, got \(error)")
        }

        // Second fetch — should NOT reuse the cached token (we cleared it).
        _ = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 0, cache: cache)

        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 4,
                       "expected OAuth1 + API(401) + OAuth2 + API(200) = 4 calls")
    }

    // MARK: - Cache integration

    func testFetchCachesOnSuccessForTTLGreaterThanZero() async throws {
        let payload = Data(#"[{"id":"1000"}]"#.utf8)
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), payload))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        let first = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 60, cache: cache)
        XCTAssertEqual(first, payload)

        // Second fetch: cache hit, no further HTTP.
        let second = try await client.fetch(path: "v3/Rail/TRA/Station", cacheTTL: 60, cache: cache)
        XCTAssertEqual(second, payload)
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 2,
                       "TTL>0 second fetch should hit cache, not HTTP")
    }

    func testFetchTTLZeroDoesNotCache() async throws {
        let payload1 = Data(#"[{"v":1}]"#.utf8)
        let payload2 = Data(#"[{"v":2}]"#.utf8)
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), Self.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), payload1)),
            .success((MockURLProtocol.httpResponse(200), payload2))
        ]
        let client = Self.makeClient()
        let cache = Cache()

        let first = try await client.fetch(path: "v2/Bus/RealTimeNearStop", cacheTTL: 0, cache: cache)
        let second = try await client.fetch(path: "v2/Bus/RealTimeNearStop", cacheTTL: 0, cache: cache)
        XCTAssertEqual(first, payload1)
        XCTAssertEqual(second, payload2, "TTL=0 must always re-fetch from network")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 3,
                       "OAuth + 2 fresh fetches = 3 calls")
    }

    // MARK: - Helpers

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func makeClient() -> TDXClient {
        TDXClient(
            session: makeSession(),
            credentialProvider: { (clientId: "test-id", clientSecret: "test-secret") },
            retryDelayNanoseconds: 0
        )
    }

    private static func tokenJSON() -> Data {
        Data(#"{"access_token":"test-access-token","expires_in":86400}"#.utf8)
    }
}
