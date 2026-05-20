// Tests/CheTransportMCPTests/RailToolsTests.swift
import XCTest
@testable import CheTransportMCP

final class RailToolsTests: XCTestCase {
    func testListSystemsReturnsAllEight() {
        let systems = RailTools.listSystems()
        XCTAssertEqual(systems.count, 8)
        XCTAssertTrue(systems.contains { $0["code"] == "TRA" })
        XCTAssertTrue(systems.contains { $0["code"] == "KLRT" })
    }
}
