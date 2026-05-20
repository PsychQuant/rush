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

    func testFuzzyMatchStations() {
        let stations = [
            RailStation(stationID: "1000", stationName: LocalizedName(zhTw: "臺北", en: "Taipei"), stationPosition: nil),
            RailStation(stationID: "1020", stationName: LocalizedName(zhTw: "板橋", en: "Banqiao"), stationPosition: nil),
            RailStation(stationID: "1080", stationName: LocalizedName(zhTw: "新竹", en: "Hsinchu"), stationPosition: nil)
        ]
        let matches = RailTools.fuzzyMatch(query: "台北", in: stations)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].stationID, "1000", "台北 should match 臺北")
    }

    func testFuzzyMatchMultipleResults() {
        let stations = [
            RailStation(stationID: "R10", stationName: LocalizedName(zhTw: "中山", en: "Zhongshan"), stationPosition: nil),
            RailStation(stationID: "G14", stationName: LocalizedName(zhTw: "中山國中", en: "Zhongshan JHS"), stationPosition: nil)
        ]
        let matches = RailTools.fuzzyMatch(query: "中山", in: stations)
        XCTAssertEqual(matches.count, 2, "Both stations contain 中山")
    }

    func testValidateDateAccepts() {
        XCTAssertNoThrow(try RailTools.validateDate("2026-05-20"))
    }

    func testValidateDateRejects() {
        XCTAssertThrowsError(try RailTools.validateDate("2026/5/20"))
        XCTAssertThrowsError(try RailTools.validateDate("not-a-date"))
    }
}
