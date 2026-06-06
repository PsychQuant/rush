// Tests/RushTests/RailBusRouteToolTests.swift
import XCTest
import MCP
@testable import Rush

/// Executor tests for `rail_bus_route` (Stage 3b, #rail-bus-routing). Inline FIFO
/// fixtures drive the exact fetch order: railStation → metro StationOfRoute →
/// busStop → [s2s, frequency, lineTransfer, OD, liveBoard] (rail leg) →
/// busStopOfRoute → busSchedule. Rail leg is TRA→TRA (中壢→臺北) so the metro
/// graph stays out of the way; the bus leg boards at the name-matched 臺北車站.
/// Asserts structure + source labels; exact arithmetic lives in RailBusRouterTests.
final class RailBusRouteToolTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    private func d(_ s: String) -> Data { Data(s.utf8) }
    private func parse(_ r: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(r).utf8)) as? [String: Any])
    }
    private func call(_ args: [String: Value]) async -> CallTool.Result {
        await TransitTools.handleCall(name: "rail_bus_route", arguments: args,
                                      client: TestSupport.mockClient(), cache: Cache())
    }

    // MARK: - Rail-leg fixtures (TRA 中壢 1080 → 臺北 1000)

    private let traStations = """
    [ {"StationID":"1080","StationName":{"Zh_tw":"中壢","En":"Zhongli"}},
      {"StationID":"1000","StationName":{"Zh_tw":"臺北","En":"Taipei"}} ]
    """
    private let metroSOR = """
    [ {"LineID":"BL","Stations":[
        {"Sequence":1,"StationID":"BL12","StationName":{"Zh_tw":"台北車站"}},
        {"Sequence":2,"StationID":"BL11","StationName":{"Zh_tw":"西門"}} ]} ]
    """
    private let metroS2S = #"[ {"LineID":"BL","TravelTimes":[{"FromStationID":"BL12","ToStationID":"BL11","RunTime":120,"StopTime":0}]} ]"#
    private let metroFreq = """
    [ {"LineID":"BL","ServiceDay":{"Monday":true,"Tuesday":true,"Wednesday":true,"Thursday":true,"Friday":true,"Saturday":true,"Sunday":true},
       "Headways":[{"StartTime":"00:00","EndTime":"24:00","MinHeadwayMins":4,"MaxHeadwayMins":6}]} ]
    """
    private let metroLineTransfer = "[]"
    private let odTimetable = """
    [ {"TrainInfo":{"TrainNo":"100","TrainTypeName":{"Zh_tw":"自強"}},
       "StopTimes":[
        {"StationID":"1080","StationName":{"Zh_tw":"中壢"},"ArrivalTime":"08:00","DepartureTime":"08:00"},
        {"StationID":"1000","StationName":{"Zh_tw":"臺北"},"ArrivalTime":"08:45","DepartureTime":"08:45"} ]} ]
    """
    private let liveBoard = #"[{"TrainNo":"100","DelayTime":0}]"#

    // MARK: - Bus-leg fixtures

    // Happy: 臺北車站 (name-matched to transfer 臺北) → 迄站 on route 299.
    private let busStopsHappy = """
    [ {"StopUID":"TPE1","StopName":{"Zh_tw":"臺北車站(忠孝)"}},
      {"StopUID":"D1","StopName":{"Zh_tw":"迄站"}} ]
    """
    private let stopOfRouteHappy = """
    [ {"RouteUID":"299","RouteName":{"Zh_tw":"299"},"Direction":0,"Stops":[
        {"StopUID":"TPE1","StopName":{"Zh_tw":"臺北車站(忠孝)"}},
        {"StopUID":"D1","StopName":{"Zh_tw":"迄站"}} ]} ]
    """
    // Trip departs the transfer at 08:55 (≥ rail arrival 08:45 + walk 5 = 08:50) → scheduled board + arrival.
    private let scheduleHappy = """
    [ {"RouteUID":"299","RouteName":{"Zh_tw":"299"},"Direction":0,"Timetables":[
        {"TripID":"t1","StopTimes":[
          {"StopSequence":1,"StopUID":"TPE1","ArrivalTime":"08:55","DepartureTime":"08:55"},
          {"StopSequence":2,"StopUID":"D1","ArrivalTime":"09:10","DepartureTime":"09:10"} ]} ]} ]
    """

    // (a) Happy rail→bus: TRA leg(s) + one bus leg, transfer at 臺北, scheduled arrival.
    func testHappyRailBusPath() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStopsHappy),
                                       d(metroS2S), d(metroFreq), d(metroLineTransfer), d(odTimetable), d(liveBoard),
                                       d(stopOfRouteHappy), d(scheduleHappy)])
        let r = await call(["from": .string("中壢"), "transfer": .string("臺北"),
                            "to_stop": .string("迄站"), "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(legs.count, 2)
        XCTAssertEqual(legs.first?["mode"] as? String, "TRA")
        XCTAssertEqual(legs.last?["mode"] as? String, "Bus")
        XCTAssertEqual(legs.last?["line"] as? String, "299")
        XCTAssertEqual(legs.last?["from_name"] as? String, "臺北車站(忠孝)")
        XCTAssertEqual(legs.last?["to_name"] as? String, "迄站")
        XCTAssertEqual(legs.last?["arrival_source"] as? String, "scheduled")
        let transfers = try XCTUnwrap(o["transfers"] as? [[String: Any]])
        XCTAssertEqual(transfers.first?["at_name"] as? String, "臺北")
        XCTAssertEqual(transfers.first?["walk_min"] as? Int, 5)
        XCTAssertEqual(o["transfer_count"] as? Int, 1)
        XCTAssertNotNil(o["arrival_time"] as? String)
        XCTAssertNil(o["auto_selected_transfer"], "explicit transfer must not emit auto marker")
    }

    // (b) Ambiguous to_stop → matches. Short-circuits after railStation + metroSOR + busStop.
    func testAmbiguousToStopReturnsMatches() async throws {
        let busStopsAmbig = """
        [ {"StopUID":"M1","StopName":{"Zh_tw":"市政府"}},
          {"StopUID":"M2","StopName":{"Zh_tw":"市政府"}} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStopsAmbig)])
        let r = await call(["from": .string("中壢"), "transfer": .string("臺北"),
                            "to_stop": .string("市政府"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["ambiguous"] as? String, "to_stop")
        XCTAssertEqual((o["matches"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(o["legs"])
    }

    // (c) Rail leg unreachable (empty OD timetable) → empty routes + note, no bus fetch.
    func testRailUnreachableEmptyWithNote() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStopsHappy),
                                       d(metroS2S), d(metroFreq), d(metroLineTransfer), d("[]")])
        let r = await call(["from": .string("中壢"), "transfer": .string("臺北"),
                            "to_stop": .string("迄站"), "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
        XCTAssertNil(o["legs"])
    }

    // (d) No name-matched boarding stop at the transfer → empty routes + note (rail leg ran).
    func testNoQualifyingTransferStopEmptyWithNote() async throws {
        let busStopsNoMatch = """
        [ {"StopUID":"D1","StopName":{"Zh_tw":"迄站"}},
          {"StopUID":"X1","StopName":{"Zh_tw":"某市場"}} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(busStopsNoMatch),
                                       d(metroS2S), d(metroFreq), d(metroLineTransfer), d(odTimetable), d(liveBoard)])
        let r = await call(["from": .string("中壢"), "transfer": .string("臺北"),
                            "to_stop": .string("迄站"), "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
        XCTAssertNil(o["legs"])
    }

    // MARK: - Stage 3b-ii: auto transfer-hub (transfer omitted)

    // metro SOR WITHOUT 台北車站 so 臺北車站(忠孝) name-matches only the TRA 臺北 → exactly one hub.
    private let autoMetroSOR = """
    [ {"LineID":"BL","Stations":[
        {"Sequence":1,"StationID":"BL11","StationName":{"Zh_tw":"西門"}},
        {"Sequence":2,"StationID":"BL10","StationName":{"Zh_tw":"龍山寺"}} ]} ]
    """

    // (e) Auto happy: transfer omitted → reverse search picks 臺北, rail+bus legs + auto_selected_transfer.
    //     Auto fetch order: traStations, metroSOR, busStop, busStopOfRoute, busSchedule, then per-hub composeRailLeg.
    func testAutoHubHappyPath() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(autoMetroSOR), d(busStopsHappy),
                                       d(stopOfRouteHappy), d(scheduleHappy),
                                       d("[]"), d("[]"), d("[]"), d(odTimetable), d(liveBoard)])
        let r = await call(["from": .string("中壢"), "to_stop": .string("迄站"),
                            "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["auto_selected_transfer"] as? String, "臺北")
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.first?["mode"] as? String, "TRA")
        XCTAssertEqual(legs.last?["mode"] as? String, "Bus")
        XCTAssertEqual(legs.last?["from_name"] as? String, "臺北車站(忠孝)")
        XCTAssertEqual(o["transfer_count"] as? Int, 1)
    }

    // (f) Auto, no qualifying hub: no upstream stop name-matches a rail station → empty + note.
    //     Short-circuits after busStopOfRoute (no schedule / rail fetch).
    func testAutoHubNoQualifyingHubEmptyWithNote() async throws {
        let busStopsNoHub = """
        [ {"StopUID":"D1","StopName":{"Zh_tw":"迄站"}},
          {"StopUID":"NS","StopName":{"Zh_tw":"某市場"}} ]
        """
        let stopOfRouteNoHub = """
        [ {"RouteUID":"X","RouteName":{"Zh_tw":"X"},"Direction":0,"Stops":[
            {"StopUID":"NS","StopName":{"Zh_tw":"某市場"}},
            {"StopUID":"D1","StopName":{"Zh_tw":"迄站"}} ]} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(autoMetroSOR), d(busStopsNoHub), d(stopOfRouteNoHub)])
        let r = await call(["from": .string("中壢"), "to_stop": .string("迄站"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
        XCTAssertNil(o["legs"])
        XCTAssertNil(o["auto_selected_transfer"])
    }

    // (g) Auto, ambiguous to_stop → matches. Short-circuits after busStop fetch.
    func testAutoHubAmbiguousToStopReturnsMatches() async throws {
        let busStopsAmbig = """
        [ {"StopUID":"M1","StopName":{"Zh_tw":"市政府"}},
          {"StopUID":"M2","StopName":{"Zh_tw":"市政府"}} ]
        """
        TestSupport.queueTokenThenAll([d(traStations), d(autoMetroSOR), d(busStopsAmbig)])
        let r = await call(["from": .string("中壢"), "to_stop": .string("市政府"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["ambiguous"] as? String, "to_stop")
        XCTAssertEqual((o["matches"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(o["legs"])
    }
}
