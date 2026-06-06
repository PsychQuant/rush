import Foundation
import MCP
@testable import Rush

/// Shared helpers for executor + HTTP tests that drive a mocked TDXClient.
/// Centralises the mock-session wiring so individual test files stay focused
/// on the behavior under test.
enum TestSupport {

    /// A URLSession whose only protocol is MockURLProtocol — every request is
    /// served from the queued stub, nothing touches the real network.
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// A TDXClient wired to the mock session, with a constant credential
    /// provider (no keychain) and zero retry delay (so 429-retry paths run
    /// instantly).
    static func mockClient() -> TDXClient {
        TDXClient(
            session: mockSession(),
            credentialProvider: { (clientId: "test-id", clientSecret: "test-secret") },
            retryDelayNanoseconds: 0
        )
    }

    static func tokenJSON() -> Data {
        Data(#"{"access_token":"test-access-token","expires_in":86400}"#.utf8)
    }

    /// Reset the stub and queue an OAuth token response followed by one API
    /// response. Most executors do exactly one fetch (plus the implicit token
    /// fetch on a fresh client), so this is the common setup.
    static func queueTokenThen(_ apiResponse: Data, status: Int = 200) {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), tokenJSON())),
            .success((MockURLProtocol.httpResponse(status), apiResponse))
        ]
    }

    /// Reset the stub and queue an OAuth token + N API responses, for
    /// executors that fan out (e.g. rail_search_stations with no system arg
    /// makes one call per RailSystem). Order of consumption is FIFO; only use
    /// for serial (non-parallel) fan-outs to keep determinism.
    static func queueTokenThenAll(_ apiResponses: [Data], status: Int = 200) {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        var responses: [Result<(HTTPURLResponse, Data), Error>] = [
            .success((MockURLProtocol.httpResponse(200), tokenJSON()))
        ]
        for body in apiResponses {
            responses.append(.success((MockURLProtocol.httpResponse(status), body)))
        }
        MockURLProtocol.stub?.queuedResponses = responses
    }

    /// Extract the first text content block from a CallTool.Result.
    static func textContent(_ result: CallTool.Result) -> String {
        for content in result.content {
            if case .text(let text, _, _) = content { return text }
        }
        return ""
    }
}
