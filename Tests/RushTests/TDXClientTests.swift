// Tests/RushTests/TDXClientTests.swift
import XCTest
@testable import Rush

final class TDXClientTests: XCTestCase {
    func testParseOAuthResponse() throws {
        let url = Bundle.module.url(forResource: "oauth_response", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let token = try TDXClient.parseTokenResponse(data)
        XCTAssertEqual(token.accessToken, "eyJhbGciOi...")
        XCTAssertEqual(token.expiresIn, 86400)
    }

    func testCacheKeyDerivation() {
        let key1 = TDXClient.cacheKey(path: "/v3/Rail/TRA/Station", queryItems: [
            URLQueryItem(name: "$top", value: "10"),
            URLQueryItem(name: "$format", value: "JSON")
        ])
        let key2 = TDXClient.cacheKey(path: "/v3/Rail/TRA/Station", queryItems: [
            URLQueryItem(name: "$format", value: "JSON"),
            URLQueryItem(name: "$top", value: "10")
        ])
        XCTAssertEqual(key1, key2, "Cache key must be order-independent")
    }
}
