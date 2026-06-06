import Foundation

/// Intercepts requests routed through a `URLSession` whose configuration
/// registers `MockURLProtocol` in its `protocolClasses` list, and serves
/// canned responses queued by the test. Used by `TDXClientHTTPTests` to
/// exercise OAuth, 429 retry, 401 token invalidation, and HTTP error
/// handling without touching the real TDX network.
///
/// Usage:
///
/// ```swift
/// override func setUp() {
///     super.setUp()
///     MockURLProtocol.stub = MockURLProtocol.Stub()
/// }
/// override func tearDown() {
///     MockURLProtocol.stub = nil
///     super.tearDown()
/// }
/// // …
/// MockURLProtocol.stub?.queuedResponses = [
///     .success((Self.httpResponse(200), tokenJSON)),
///     .success((Self.httpResponse(429), Data())),
///     .success((Self.httpResponse(200), tdxJSON))
/// ]
/// ```
///
/// Thread-safety: the underlying `static var` is fine for serial test
/// execution (which is the SwiftPM default within a test target), but
/// would need locking if a test target ever enables parallel test runs.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        /// Append to this on every request the protocol sees, so tests can
        /// assert call count, URL paths, headers, body, etc.
        var calls: [URLRequest] = []
        /// Drained FIFO. Each request consumes one entry. Tests that expect
        /// `n` HTTP calls should queue `n` responses up front.
        var queuedResponses: [Result<(HTTPURLResponse, Data), Error>] = []
    }

    nonisolated(unsafe) static var stub: Stub?

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        // Only handle requests when a test has set up a stub. Outside of
        // tests this protocol won't intercept anything.
        return stub != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard var stub = MockURLProtocol.stub, !stub.queuedResponses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost,
                userInfo: [NSLocalizedDescriptionKey: "MockURLProtocol: no queued responses (\(request.url?.absoluteString ?? "?"))"]))
            return
        }
        let nextResponse = stub.queuedResponses.removeFirst()
        stub.calls.append(request)
        MockURLProtocol.stub = stub

        switch nextResponse {
        case .success((let httpResponse, let data)):
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op: responses are delivered synchronously in startLoading().
    }

    // MARK: - Convenience builders for tests

    static func httpResponse(_ statusCode: Int,
                             url: URL = URL(string: "https://example.invalid")!,
                             headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
