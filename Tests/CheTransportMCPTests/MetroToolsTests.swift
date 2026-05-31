// Tests/CheTransportMCPTests/MetroToolsTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Tests for `metro_find_route`: the HTTP-mocked executor (direct = 0-transfer,
/// unreachable = empty+note) and the pure route-assembly / headway helpers
/// (transfer legs/transfers, per-line headway band selection).
final class MetroToolsTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    // MARK: - fixtures / synthetic builders

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func nm(_ s: String) -> LocalizedName { LocalizedName(zhTw: s, en: s) }
    private func route(_ line: String, _ id: String, _ ids: [String]) -> MetroStationOfRoute {
        MetroStationOfRoute(lineID: line, lineNo: line, routeID: id, direction: 0, lineName: nil, routeName: nil,
            stations: ids.enumerated().map { MetroRouteStation(sequence: $0.offset + 1, stationID: $0.element, stationName: nm($0.element)) })
    }
    private func s2s(_ line: String, _ id: String, _ pairs: [(String, String, Int)]) -> MetroS2STravelTime {
        MetroS2STravelTime(lineID: line, lineNo: line, routeID: id,
            travelTimes: pairs.map { MetroTravelTime(sequence: nil, fromStationID: $0.0, toStationID: $0.1, runTime: $0.2, stopTime: 0) })
    }
    private func xfer(_ fl: String, _ fs: String, _ tl: String, _ ts: String, _ minutes: Int) -> MetroLineTransfer {
        MetroLineTransfer(fromLineID: fl, fromStationID: fs, fromStationName: nm(fs),
            toLineID: tl, toStationID: ts, toStationName: nm(ts), isOnSiteTransfer: 0, transferTime: minutes, transferDescription: nil)
    }
    private func mondayMorning() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 1; c.hour = 8; c.minute = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.date(from: c)!
    }

    /// Queue token + the five datasets the executor fetches, in order:
    /// StationOfRoute, S2STravelTime, Frequency, Line, LineTransfer.
    private func queueExecutorDatasets(lineTransfer: Data) throws {
        MockURLProtocol.stub?.queuedResponses = [
            .success((MockURLProtocol.httpResponse(200), TestSupport.tokenJSON())),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_station_of_route"))),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_s2s_travel_time"))),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_frequency"))),
            .success((MockURLProtocol.httpResponse(200), try fixtureData("metro_line"))),
            .success((MockURLProtocol.httpResponse(200), lineTransfer))
        ]
    }

    private func parse(_ result: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(result).utf8)) as? [String: Any])
    }

    // MARK: - tool definition

    func testDefineToolsReturnsMetroFindRoute() {
        let tools = MetroTools.defineTools()
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "metro_find_route")
    }

    func testExecuteRejectsNonMetroSystem() async throws {
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("1000"), "to": .string("1070"), "system": .string("TRA")],
            client: TestSupport.mockClient(), cache: Cache())
        XCTAssertTrue(result.isError ?? false, "TRA is not a metro system for metro_find_route")
    }

    // MARK: - executor: direct route is a zero-transfer single leg

    func testExecuteDirectRouteIsZeroTransfer() async throws {
        // Single-line system: LineTransfer empty (no transfer edges). BL03→BL04.
        try queueExecutorDatasets(lineTransfer: Data("[]".utf8))
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("BL03"), "to": .string("BL04"), "system": .string("TRTC")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false)
        let obj = try parse(result)
        let routes = try XCTUnwrap(obj["routes"] as? [[String: Any]])
        XCTAssertFalse(routes.isEmpty)
        let r = routes[0]
        XCTAssertEqual(r["transfer_count"] as? Int, 0)
        let legs = try XCTUnwrap(r["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.count, 1, "direct route is a single leg")
        XCTAssertEqual(legs[0]["line_name"] as? String, "板南線")
        XCTAssertEqual((r["transfers"] as? [[String: Any]])?.count, 0)
        // BL03→BL04 segment is 100s → ~2 min
        XCTAssertEqual(r["travel_time_min"] as? Int, 2)
    }

    // MARK: - executor: unreachable returns empty + note

    func testExecuteUnreachableReturnsEmptyWithNote() async throws {
        try queueExecutorDatasets(lineTransfer: Data("[]".utf8))
        let result = await MetroTools.handleCall(
            name: "metro_find_route",
            arguments: ["from": .string("BL03"), "to": .string("ZZ99"), "system": .string("TRTC")],
            client: TestSupport.mockClient(), cache: Cache())

        XCTAssertFalse(result.isError ?? false, "no path is not an error")
        let obj = try parse(result)
        XCTAssertEqual((obj["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(obj["note"])
    }

    // MARK: - pure assembly: transfer route has legs + transfers

    func testAssembleTransferRouteHasLegsAndTransfers() throws {
        // Line A: A1-A2; Line B: B1-B2; transfer A2↔B1 (walk 2). A1 → B2 crosses lines.
        let graph = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2"]), route("B", "B-1", ["B1", "B2"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 120)]), s2s("B", "B-1", [("B1", "B2", 120)])],
            lineTransfer: [xfer("A", "A2", "B", "B1", 2)],
            headwayByLine: ["A": 8, "B": 8])
        let lineMeta: [String: MetroLine] = [
            "A": MetroLine(lineID: "A", lineNo: "A", lineName: nm("A線"), lineColor: "#111"),
            "B": MetroLine(lineID: "B", lineNo: "B", lineName: nm("B線"), lineColor: "#222")
        ]
        let routes = MetroTools.candidateRoutes(
            graph: graph, lineMeta: lineMeta, headwayRange: ["A": (8, 10), "B": (8, 10)],
            from: "A1", to: "B2")

        XCTAssertFalse(routes.isEmpty)
        let r = routes[0]
        XCTAssertEqual(r["transfer_count"] as? Int, 1)
        let legs = try XCTUnwrap(r["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.count, 2, "ride A, then ride B")
        XCTAssertEqual(legs[0]["line_name"] as? String, "A線")
        XCTAssertEqual(legs[1]["line_name"] as? String, "B線")
        let transfers = try XCTUnwrap(r["transfers"] as? [[String: Any]])
        XCTAssertEqual(transfers.count, 1)
        XCTAssertEqual(transfers[0]["walk_min"] as? Int, 2)
        XCTAssertNotNil(transfers[0]["wait_min"])
        XCTAssertEqual(transfers[0]["from_line"] as? String, "A")
        XCTAssertEqual(transfers[0]["to_line"] as? String, "B")
    }

    // MARK: - pure headway: per-line current-period band

    func testHeadwayByLineSelectsCurrentBand() throws {
        let frequency = try JSONDecoder().decode([MetroFrequency].self, from: fixtureData("metro_frequency"))
        let byLine = MetroTools.headwayByLine(frequency: frequency, now: mondayMorning())
        // Monday 08:00 → 平日 peak band 07:00–09:00 → MinHeadwayMins 6.
        let bl = try XCTUnwrap(byLine["BL"])
        XCTAssertEqual(bl.0, 6)
    }
}
