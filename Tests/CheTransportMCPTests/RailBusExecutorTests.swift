import XCTest
import MCP
@testable import CheTransportMCP

/// Executor-level tests for Rail + Bus tools. These drive the real dispatch
/// path (`<Module>Tools.handleCall`) against a mocked TDXClient, so they
/// exercise: argument parsing → fetch (mocked) → Codable decode → output JSON
/// assembly. Complements the pure-function tests (fuzzyMatch / validate) and
/// the HTTP-layer tests (TDXClientHTTPTests).
final class RailBusExecutorTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.stub = nil
        super.tearDown()
    }

    // MARK: - Rail

    func testRailListSystemsNeedsNoNetwork() async {
        // Pure executor — must not touch the network at all. Leave the stub
        // empty; if it tried to fetch, MockURLProtocol would error.
        MockURLProtocol.stub = MockURLProtocol.Stub()
        let result = await RailTools.handleCall(
            name: "rail_list_systems",
            arguments: [:],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("TRA"))
        XCTAssertTrue(text.contains("THSR"))
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 0, "list_systems must not fetch")
    }

    func testRailSearchStationsSystemScopedAssemblesMatches() async {
        // System-scoped → exactly one fetch (no 8-way fan-out).
        let fixture = Data("""
        {"Stations":[
          {"StationID":"1000","StationName":{"Zh_tw":"臺北","En":"Taipei"}},
          {"StationID":"1020","StationName":{"Zh_tw":"板橋","En":"Banqiao"}}
        ]}
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await RailTools.handleCall(
            name: "rail_search_stations",
            arguments: ["query": .string("台北"), "system": .string("TRA")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"station_id\":\"1000\""), "matched station id present; got \(text)")
        XCTAssertTrue(text.contains("臺北"))
        XCTAssertFalse(text.contains("板橋"), "non-matching station should be filtered out")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 2, "token + 1 station fetch")
    }

    func testRailFindTrainsPassesThroughRawJSON() async {
        // find_trains is a raw pass-through: the executor dumps the TDX body
        // verbatim. The test confirms dispatch + fetch + passthrough.
        let raw = Data(#"{"TrainTimetables":[{"TrainInfo":{"TrainNo":"152"}}]}"#.utf8)
        TestSupport.queueTokenThen(raw)

        let result = await RailTools.handleCall(
            name: "rail_find_trains",
            arguments: [
                "from": .string("1000"), "to": .string("1070"),
                "date": .string("2026-05-28"), "system": .string("TRA")
            ],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        XCTAssertTrue(TestSupport.textContent(result).contains("\"TrainNo\":\"152\""))
    }

    func testRailFindTrainsRejectsMetroSystem() async {
        // TRTC is a metro; find_trains is TRA/THSR only. Guard fires before
        // any fetch.
        MockURLProtocol.stub = MockURLProtocol.Stub()
        let result = await RailTools.handleCall(
            name: "rail_find_trains",
            arguments: [
                "from": .string("R10"), "to": .string("R28"),
                "date": .string("2026-05-28"), "system": .string("TRTC")
            ],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertEqual(result.isError, true, "metro system should be rejected for find_trains")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 0, "guard fires before fetch")
    }

    func testRailStatusStationPassesThroughRawJSON() async {
        let raw = Data(#"{"StationLiveBoards":[{"StationID":"1000","DelayTime":3}]}"#.utf8)
        TestSupport.queueTokenThen(raw)

        let result = await RailTools.handleCall(
            name: "rail_status_station",
            arguments: ["station_id": .string("1000"), "system": .string("TRA")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        XCTAssertTrue(TestSupport.textContent(result).contains("\"DelayTime\":3"))
    }

    // MARK: - Bus

    func testBusSearchRoutesAssemblesMatches() async {
        let fixture = Data("""
        [
          {"RouteUID":"TPE10001","RouteID":"10001","RouteName":{"Zh_tw":"307","En":"307"},
           "DepartureStopNameZh":"撤運站","DestinationStopNameZh":"板橋"},
          {"RouteUID":"TPE99999","RouteID":"99999","RouteName":{"Zh_tw":"藍2","En":"Blue 2"},
           "DepartureStopNameZh":"A","DestinationStopNameZh":"B"}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BusTools.handleCall(
            name: "bus_search_routes",
            arguments: ["query": .string("307"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"route_uid\":\"TPE10001\""), "307 match present; got \(text)")
        XCTAssertFalse(text.contains("TPE99999"), "non-matching route filtered out")
        XCTAssertTrue(text.contains("\"city\":\"Taipei\""))
    }

    func testBusSearchStopsAssemblesMatches() async {
        let fixture = Data("""
        [
          {"StopUID":"TPE5001","StopID":"5001","StopName":{"Zh_tw":"市政府","En":"City Hall"}},
          {"StopUID":"TPE5002","StopID":"5002","StopName":{"Zh_tw":"國父紀念館","En":"SYS Memorial Hall"}}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BusTools.handleCall(
            name: "bus_search_stops",
            arguments: ["query": .string("市政府"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"stop_uid\":\"TPE5001\""))
        XCTAssertFalse(text.contains("TPE5002"))
    }

    func testBusFindRoutesIntersectsStopOfRoute() async {
        // Two routes; only the first visits BOTH from_stop and to_stop.
        let fixture = Data("""
        [
          {"RouteUID":"R_A","RouteName":{"Zh_tw":"A線","En":"A"},"Direction":0,
           "Stops":[{"StopUID":"S1","StopName":{"Zh_tw":"起","En":"start"}},
                    {"StopUID":"S2","StopName":{"Zh_tw":"中","En":"mid"}},
                    {"StopUID":"S3","StopName":{"Zh_tw":"迄","En":"end"}}]},
          {"RouteUID":"R_B","RouteName":{"Zh_tw":"B線","En":"B"},"Direction":0,
           "Stops":[{"StopUID":"S1","StopName":{"Zh_tw":"起","En":"start"}},
                    {"StopUID":"S9","StopName":{"Zh_tw":"別","En":"other"}}]}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BusTools.handleCall(
            name: "bus_find_routes",
            arguments: [
                "from_stop": .string("S1"), "to_stop": .string("S3"),
                "city": .string("Taipei")
            ],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"route_uid\":\"R_A\""), "R_A visits both stops")
        XCTAssertFalse(text.contains("R_B"), "R_B only visits S1, not S3 — excluded")
    }

    func testBusStatusArrivalsAssemblesETA() async {
        let fixture = Data("""
        [
          {"StopUID":"S1","RouteUID":"R_A","RouteName":{"Zh_tw":"307"},"Direction":0,
           "EstimateTime":120,"StopStatus":0}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BusTools.handleCall(
            name: "bus_status_arrivals",
            arguments: ["stop_id": .string("S1"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"eta_seconds\":120"))
        XCTAssertTrue(text.contains("\"route_name\":\"307\""))
    }

    func testBusStatusPositionsAssemblesPositions() async {
        let fixture = Data("""
        [
          {"PlateNumb":"KKA-1234","RouteUID":"R_A","RouteName":{"Zh_tw":"307"},
           "Direction":0,"BusPosition":{"PositionLat":25.04,"PositionLon":121.56}}
        ]
        """.utf8)
        TestSupport.queueTokenThen(fixture)

        let result = await BusTools.handleCall(
            name: "bus_status_positions",
            arguments: ["route_name": .string("307"), "city": .string("Taipei")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertNotEqual(result.isError, true)
        let text = TestSupport.textContent(result)
        XCTAssertTrue(text.contains("\"plate\":\"KKA-1234\""))
        // NOTE: lat/lon are emitted as raw Doubles, so JSONSerialization
        // renders 25.04 as "25.039999999999999" (IEEE-754 noise). We assert
        // the leading digits rather than the literal to stay robust; the
        // precision noise itself is a known minor output-quality issue
        // affecting every geo-emitting executor.
        XCTAssertTrue(text.contains("\"lat\":25.0"), "bus position lat present; got \(text)")
    }

    func testBusRejectsInvalidCity() async {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        let result = await BusTools.handleCall(
            name: "bus_search_routes",
            arguments: ["query": .string("307"), "city": .string("Atlantis")],
            client: TestSupport.mockClient(),
            cache: Cache()
        )
        XCTAssertEqual(result.isError, true, "invalid city should error before fetch")
        XCTAssertEqual(MockURLProtocol.stub?.calls.count, 0)
    }
}
