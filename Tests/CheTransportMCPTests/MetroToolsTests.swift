// Tests/CheTransportMCPTests/MetroToolsTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Tests for the metro direct-O/D routing tool: the pure assembly core
/// (intersection / direction / segment accumulation / headway selection) plus
/// the HTTP-mocked executor (short-circuit on no-direct, sparse-data sentinels).
final class MetroToolsTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    // MARK: - Fixtures / helpers

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: fixtureData(name))
    }

    /// A fixed Monday 08:00 Asia/Taipei → weekday (平日) peak band (07:00–09:00).
    private func mondayMorning() -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 1; comps.hour = 8; comps.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.date(from: comps)!
    }

    private func loadModels() throws -> ([MetroStationOfRoute], [MetroS2STravelTime], [MetroFrequency], [MetroLine]) {
        (try decode([MetroStationOfRoute].self, "metro_station_of_route"),
         try decode([MetroS2STravelTime].self, "metro_s2s_travel_time"),
         try decode([MetroFrequency].self, "metro_frequency"),
         try decode([MetroLine].self, "metro_line"))
    }

    // MARK: - 2.1 tool definition

    func testDefineToolsReturnsMetroFindRoute() {
        let tools = MetroTools.defineTools()
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "metro_find_route")
    }

    // MARK: - 2.2 routing core: intersection + direction + accumulation

    func testAssembleFindsForwardRouteWithTimeAndHeadway() throws {
        let (sor, s2s, freq, line) = try loadModels()
        let routes = MetroTools.assembleDirectRoutes(
            from: "BL03", to: "BL04",
            stationOfRoute: sor, s2s: s2s, frequency: freq, line: line,
            now: mondayMorning())

        XCTAssertEqual(routes.count, 1, "only the forward route BL-1 has fromSeq < toSeq")
        let r = routes[0]
        XCTAssertEqual(r["route_id"] as? String, "BL-1")
        XCTAssertEqual(r["direction"] as? Int, 0)
        XCTAssertEqual(r["line_name"] as? String, "板南線")
        XCTAssertEqual(r["line_color"] as? String, "#0a59ae")
        // BL03→BL04: one segment runTime 100s, last-segment stopTime excluded → round(100/60)=2
        XCTAssertEqual(r["travel_time_min"] as? Int, 2)
        // Monday 08:00 → 平日 peak band 07:00–09:00 → MinHeadwayMins 6
        XCTAssertEqual(r["headway_min"] as? Int, 6)
        XCTAssertEqual(r["stations_count"] as? Int, 2)
    }

    func testAssembleAccumulatesMultipleSegments() throws {
        let (sor, s2s, freq, line) = try loadModels()
        let routes = MetroTools.assembleDirectRoutes(
            from: "BL01", to: "BL04",
            stationOfRoute: sor, s2s: s2s, frequency: freq, line: line,
            now: mondayMorning())
        XCTAssertEqual(routes.count, 1)
        // runTime 120+90+100=310; intermediate stopTime 30+25=55 (last excluded) → 365s → round=6
        XCTAssertEqual(routes[0]["travel_time_min"] as? Int, 6)
        XCTAssertEqual(routes[0]["stations_count"] as? Int, 4)
    }

    /// Regression for the real-TDX case: S2STravelTime stores segments in ONE
    /// direction only (descending), yet a forward A→B query must still compute a
    /// travel time. Run-time is symmetric, so reverse-stored segments must match.
    func testAssembleUsesReverseStoredSegmentsForForwardQuery() throws {
        let (sor, _, freq, line) = try loadModels()
        // Only the reverse (descending) segments, mimicking how TDX stores 板南線.
        let reverseS2S = try JSONDecoder().decode([MetroS2STravelTime].self, from: Data("""
        [{ "LineID": "BL", "RouteID": "BL-1", "TravelTimes": [
          { "FromStationID": "BL04", "ToStationID": "BL03", "RunTime": 100, "StopTime": 0 },
          { "FromStationID": "BL03", "ToStationID": "BL02", "RunTime": 90, "StopTime": 25 },
          { "FromStationID": "BL02", "ToStationID": "BL01", "RunTime": 120, "StopTime": 30 }
        ]}]
        """.utf8))
        let routes = MetroTools.assembleDirectRoutes(
            from: "BL03", to: "BL04",
            stationOfRoute: sor, s2s: reverseS2S, frequency: freq, line: line,
            now: mondayMorning())
        XCTAssertEqual(routes.count, 1)
        // BL03→BL04 forward must match the reverse-stored BL04→BL03 segment (100s → 2 min),
        // NOT fall through to the -1 sentinel.
        XCTAssertEqual(routes[0]["travel_time_min"] as? Int, 2)
    }

    func testAssembleNoSharedRouteReturnsEmpty() throws {
        let (sor, s2s, freq, line) = try loadModels()
        let routes = MetroTools.assembleDirectRoutes(
            from: "BL03", to: "G99",
            stationOfRoute: sor, s2s: s2s, frequency: freq, line: line,
            now: mondayMorning())
        XCTAssertTrue(routes.isEmpty)
    }

    // MARK: - 2.2 executor: no-direct short-circuit + transfer note

    func testExecuteNoDirectRouteIsEmptyWithNoteAndSingleFetch() async throws {
        // Queue ONLY token + StationOfRoute. If the executor fails to short-circuit
        // and fetches again, the FIFO mock has nothing left → the fetch throws.
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), TestSupport.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_station_of_route")))
        ]
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("BL03"), "to": .string("G99"), "system": .string("TRTC")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false, "no-direct is not an error")
        let json = TestSupport.textContent(result)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual((obj["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(obj["note"], "transfer hint should be present when no direct route exists")
        // Exactly 2 HTTP calls: token + the single StationOfRoute gate fetch.
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 2)
    }

    // MARK: - 2.2 executor: sparse-data system → sentinels, not error

    func testExecuteSparseDataReturnsSentinels() async throws {
        let empty = Data("[]".utf8)
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), TestSupport.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_station_of_route"))),
            .success((MockURLProtocol.httpResponse(200), empty)),   // S2STravelTime empty
            .success((MockURLProtocol.httpResponse(200), empty)),   // Frequency empty
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_line")))
        ]
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("BL03"), "to": .string("BL04"), "system": .string("TRTC")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false)
        let json = TestSupport.textContent(result)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let routes = try XCTUnwrap(obj["routes"] as? [[String: Any]])
        XCTAssertEqual(routes.count, 1, "the route is still found from StationOfRoute")
        XCTAssertEqual(routes[0]["travel_time_min"] as? Int, -1, "missing travel-time data → sentinel")
        XCTAssertEqual(routes[0]["headway_min"] as? Int, -1, "missing headway data → sentinel")
        XCTAssertEqual(routes[0]["line_name"] as? String, "板南線", "Line lookup still enriches the name")
    }

    // MARK: - guard: non-metro system rejected

    func testExecuteRejectsNonMetroSystem() async throws {
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("1000"), "to": .string("1070"), "system": .string("TRA")],
            client: TestSupport.mockClient(), cache: Cache())
        XCTAssertTrue(result.isError ?? false, "TRA is not a metro system for metro_find_route")
    }
}
