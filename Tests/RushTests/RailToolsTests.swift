// Tests/RushTests/RailToolsTests.swift
import XCTest
import MCP
@testable import Rush

final class RailToolsTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func parse(_ r: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(r).utf8)) as? [String: Any])
    }

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

    // MARK: - rail_route executor (#6 Stage 1)

    func testRouteLiveAdjustedEarliestArrival() async throws {
        // Executor fetches OD timetable then TrainLiveBoard. Live board delays
        // train 100 by 15 → on-time train 200 becomes earliest arrival.
        TestSupport.queueTokenThenAll([try fixtureData("tra_timetable_od"), try fixtureData("tra_train_live_board")])
        let result = await RailTools.handleCall(
            name: "rail_route",
            arguments: ["from": .string("1000"), "to": .string("3300"),
                        "depart_after": .string("08:00"), "system": .string("TRA")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false)
        let obj = try parse(result)
        let legs = try XCTUnwrap(obj["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs[0]["train_no"] as? String, "200", "live delay on 100 → 200 arrives earliest")
        XCTAssertEqual(legs[0]["source"] as? String, "live")
        XCTAssertEqual(obj["arrival_time"] as? String, "09:05")
        XCTAssertEqual(obj["transfer_count"] as? Int, 0)
    }

    func testRouteTimetableUnavailableReturnsEmptyWithNote() async throws {
        // OD timetable HTTP 500 (TDX flaky) → graceful empty + note, not error.
        TestSupport.queueTokenThen(Data("{}".utf8), status: 500)
        let result = await RailTools.handleCall(
            name: "rail_route",
            arguments: ["from": .string("1000"), "to": .string("3300"), "system": .string("TRA")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false, "TDX timetable outage is not our error")
        let obj = try parse(result)
        XCTAssertEqual((obj["legs"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(obj["note"])
    }

    func testRouteRejectsNonTRA() async throws {
        let result = await RailTools.handleCall(
            name: "rail_route",
            arguments: ["from": .string("1000"), "to": .string("1070"), "system": .string("THSR")],
            client: TestSupport.mockClient(), cache: Cache())
        XCTAssertTrue(result.isError ?? false, "rail_route is TRA-only in v1")
    }
}
