// Tests/CheTransportMCPTests/TDXClientTests.swift
import XCTest
@testable import CheTransportMCP

final class TDXClientTests: XCTestCase {
    func testParseOAuthResponse() throws {
        let url = Bundle.module.url(forResource: "oauth_response", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let token = try TDXClient.parseTokenResponse(data)
        XCTAssertEqual(token.accessToken, "eyJhbGciOi...")
        XCTAssertEqual(token.expiresIn, 86400)
    }
}
