// Tests/CheTransportMCPTests/BusRailRouteToolTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Executor tests for `bus_rail_route` (Stage 3c-i, #bus-rail-routing). FIFO fixtures
/// drive the fetch order: railStation → metro StationOfRoute → busStop → busStopOfRoute
/// → A2 → busSchedule → composeRailLeg (metro s2s/freq/lineTransfer). The rail leg is
/// metro→metro (市政府→南港 on BL) so it routes via MetroGraph headway expected-wait —
/// no timetable gate — keeping the A2-live assertions independent of wall-clock.
final class BusRailRouteToolTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    private func d(_ s: String) -> Data { Data(s.utf8) }
    private func parse(_ r: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(r).utf8)) as? [String: Any])
    }
    private func call(_ args: [String: Value]) async -> CallTool.Result {
        await TransitTools.handleCall(name: "bus_rail_route", arguments: args,
                                      client: TestSupport.mockClient(), cache: Cache())
    }

    // Rail fixtures: `to` 南港 resolves to METRO (no TRA 南港); hub 市政府 metro; BL one-hop.
    private let traStations = #"[ {"StationID":"1020","StationName":{"Zh_tw":"板橋"}} ]"#
    private let metroSOR = """
    [ {"LineID":"BL","Stations":[
        {"Sequence":1,"StationID":"BL18","StationName":{"Zh_tw":"市政府"}},
        {"Sequence":2,"StationID":"BL22","StationName":{"Zh_tw":"南港"}} ]} ]
    """
    private let metroS2S = #"[ {"LineID":"BL","TravelTimes":[{"FromStationID":"BL18","ToStationID":"BL22","RunTime":300,"StopTime":0}]} ]"#
    private let metroFreq = """
    [ {"LineID":"BL","ServiceDay":{"Monday":true,"Tuesday":true,"Wednesday":true,"Thursday":true,"Friday":true,"Saturday":true,"Sunday":true},
       "Headways":[{"StartTime":"00:00","EndTime":"24:00","MinHeadwayMins":4,"MaxHeadwayMins":6}]} ]
    """
    private let metroLineTransfer = "[]"

    // Bus: from_stop 起站 → 捷運市政府站 on route R1.
    private let busStops = """
    [ {"StopUID":"F1","StopName":{"Zh_tw":"起站"}},
      {"StopUID":"M1","StopName":{"Zh_tw":"捷運市政府站"}} ]
    """
    private let stopOfRoute = """
    [ {"RouteUID":"R1","RouteName":{"Zh_tw":"R1"},"Direction":0,"Stops":[
        {"StopUID":"F1","StopName":{"Zh_tw":"起站"}},
        {"StopUID":"M1","StopName":{"Zh_tw":"捷運市政府站"}} ]} ]
    """
    private let a2Live = #"[{"StopUID":"F1","RouteUID":"R1","RouteName":{"Zh_tw":"R1"},"Direction":0,"EstimateTime":120,"StopStatus":0}]"#
    private let scheduleTimetabled = """
    [ {"RouteUID":"R1","RouteName":{"Zh_tw":"R1"},"Direction":0,"Timetables":[
        {"TripID":"t1","StopTimes":[
          {"StopSequence":1,"StopUID":"F1","ArrivalTime":"08:00","DepartureTime":"08:00"},
          {"StopSequence":2,"StopUID":"M1","ArrivalTime":"08:10","DepartureTime":"08:10"} ]} ]} ]
    """
    // Frequency-only: a headway band, no timetable → bus arrival unknown.
    private let scheduleFreqOnly = """
    [ {"RouteUID":"R1","RouteName":{"Zh_tw":"R1"},"Direction":0,"Frequencys":[
        {"StartTime":"00:00","EndTime":"24:00","MinHeadwayMins":10,"MaxHeadwayMins":15} ]} ]
    """

    // FIFO for a one-hop metro rail leg: …, composeRailLeg = s2s, freq, lineTransfer (no TRA OD).
    private func happyQueue(a2: String, schedule: String) -> [Data] {
        [d(traStations), d(metroSOR), d(busStops), d(stopOfRoute), d(a2), d(schedule),
         d(metroS2S), d(metroFreq), d(metroLineTransfer)]
    }

    // (a) Explicit happy bus→rail: A2-live board, bus leg then metro legs, no auto marker.
    func testExplicitBusRailWithLiveBoard() async throws {
        TestSupport.queueTokenThenAll(happyQueue(a2: a2Live, schedule: scheduleTimetabled))
        let r = await call(["from_stop": .string("起站"), "to": .string("南港"),
                            "city": .string("Taipei"), "transfer": .string("市政府"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.first?["mode"] as? String, "Bus")
        XCTAssertEqual(legs.first?["from_name"] as? String, "起站")
        XCTAssertEqual(legs.first?["to_name"] as? String, "捷運市政府站")
        XCTAssertEqual(legs.first?["source"] as? String, "live")          // A2 present
        XCTAssertEqual(legs.last?["mode"] as? String, "Metro")
        XCTAssertEqual(o["transfer_count"] as? Int, 1)
        XCTAssertNotNil(o["arrival_time"] as? String)
        XCTAssertNil(o["auto_selected_transfer"], "explicit transfer must not emit auto marker")
        XCTAssertNil(o["approx_note"], "timetabled bus → exact rail anchor, no approximation")
    }

    // (b) Auto happy: transfer omitted → forward search picks 市政府, auto_selected_transfer set.
    func testAutoBusRailHappyPath() async throws {
        TestSupport.queueTokenThenAll(happyQueue(a2: a2Live, schedule: scheduleTimetabled))
        let r = await call(["from_stop": .string("起站"), "to": .string("南港"),
                            "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["auto_selected_transfer"] as? String, "市政府")
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.first?["mode"] as? String, "Bus")
        XCTAssertEqual(legs.last?["mode"] as? String, "Metro")
        XCTAssertEqual(o["transfer_count"] as? Int, 1)
    }

    // (c) Ambiguous from_stop → matches. `to` resolves first (unique), then busStop short-circuits.
    func testAmbiguousFromStopReturnsMatches() async throws {
        let busStopsAmbig = """
        [ {"StopUID":"G1","StopName":{"Zh_tw":"市府"}},
          {"StopUID":"G2","StopName":{"Zh_tw":"市府"}} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStopsAmbig)])
        let r = await call(["from_stop": .string("市府"), "to": .string("南港"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["ambiguous"] as? String, "from_stop")
        XCTAssertEqual((o["matches"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(o["legs"])
    }

    // (d) No qualifying alight-hub: no downstream stop name-matches a rail station → empty + note.
    func testNoQualifyingHubEmptyWithNote() async throws {
        let stopOfRouteNoHub = """
        [ {"RouteUID":"R1","RouteName":{"Zh_tw":"R1"},"Direction":0,"Stops":[
            {"StopUID":"F1","StopName":{"Zh_tw":"起站"}},
            {"StopUID":"X1","StopName":{"Zh_tw":"某市場"}} ]} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStops), d(stopOfRouteNoHub), d(a2Live), d(scheduleTimetabled)])
        let r = await call(["from_stop": .string("起站"), "to": .string("南港"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
        XCTAssertNil(o["legs"])
    }

    // (e) Frequency-only bus (no timetable, no A2) → rail board-anchored + approx note.
    func testFrequencyOnlyBusApproxNote() async throws {
        TestSupport.queueTokenThenAll(happyQueue(a2: "[]", schedule: scheduleFreqOnly))
        let r = await call(["from_stop": .string("起站"), "to": .string("南港"),
                            "city": .string("Taipei"), "transfer": .string("市政府"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.first?["source"] as? String, "frequency")     // no A2, no timetable
        XCTAssertEqual(legs.last?["mode"] as? String, "Metro")
        XCTAssertNotNil(o["approx_note"], "frequency-only bus → approximate rail anchor must be disclosed")
        XCTAssertNotNil(o["arrival_time"] as? String)
    }
}
