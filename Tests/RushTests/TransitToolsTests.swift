// Tests/RushTests/TransitToolsTests.swift
import XCTest
import MCP
@testable import Rush

/// Executor tests for `transit_route` (#multimodal-routing). Inline fixtures + the
/// FIFO MockURLProtocol stub drive the exact fetch order
/// (TRA stations → metro StationOfRoute → [s2s, frequency, lineTransfer] → OD → live board).
/// Synthetic 板南線 corridor: 板橋(BL07) — 台北車站(BL12) — 西門(BL11) — 市政府(BL18),
/// 中山 (R11/G14) is ONE logical station (two platforms); the disambiguation case
/// uses the vague query 山 which matches two DISTINCT stations (中山 + 松山).
final class TransitToolsTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    private func d(_ s: String) -> Data { Data(s.utf8) }
    private func parse(_ r: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(r).utf8)) as? [String: Any])
    }

    // MARK: - Fixtures

    private let traStations = """
    [ {"StationID":"1080","StationName":{"Zh_tw":"中壢","En":"Zhongli"}},
      {"StationID":"1020","StationName":{"Zh_tw":"板橋","En":"Banqiao"}},
      {"StationID":"1000","StationName":{"Zh_tw":"臺北","En":"Taipei"}} ]
    """
    private let metroSOR = """
    [ {"LineID":"BL","Stations":[
        {"Sequence":1,"StationID":"BL07","StationName":{"Zh_tw":"板橋"}},
        {"Sequence":2,"StationID":"BL12","StationName":{"Zh_tw":"台北車站"}},
        {"Sequence":3,"StationID":"BL11","StationName":{"Zh_tw":"西門"}},
        {"Sequence":4,"StationID":"BL18","StationName":{"Zh_tw":"市政府"}} ]},
      {"LineID":"R","Stations":[
        {"Sequence":1,"StationID":"R10","StationName":{"Zh_tw":"台北車站"}},
        {"Sequence":2,"StationID":"R11","StationName":{"Zh_tw":"中山"}} ]},
      {"LineID":"G","Stations":[
        {"Sequence":1,"StationID":"G14","StationName":{"Zh_tw":"中山"}},
        {"Sequence":2,"StationID":"G15","StationName":{"Zh_tw":"松山"}} ]} ]
    """
    private let metroS2S = """
    [ {"LineID":"BL","TravelTimes":[
        {"FromStationID":"BL07","ToStationID":"BL12","RunTime":300,"StopTime":0},
        {"FromStationID":"BL12","ToStationID":"BL11","RunTime":120,"StopTime":0},
        {"FromStationID":"BL11","ToStationID":"BL18","RunTime":180,"StopTime":0} ]} ]
    """
    private let metroFreq = """
    [ {"LineID":"BL","ServiceDay":{"Monday":true,"Tuesday":true,"Wednesday":true,"Thursday":true,"Friday":true,"Saturday":true,"Sunday":true},
       "Headways":[{"StartTime":"00:00","EndTime":"24:00","MinHeadwayMins":4,"MaxHeadwayMins":6}]} ]
    """
    private let metroLineTransfer = "[]"
    private let odTimetable = """
    [ {"TrainInfo":{"TrainNo":"100","TrainTypeName":{"Zh_tw":"自強"}},
       "StopTimes":[
        {"StationID":"1080","StationName":{"Zh_tw":"中壢"},"ArrivalTime":"08:00","DepartureTime":"08:00"},
        {"StationID":"1020","StationName":{"Zh_tw":"板橋"},"ArrivalTime":"08:30","DepartureTime":"08:31"},
        {"StationID":"1000","StationName":{"Zh_tw":"臺北"},"ArrivalTime":"08:45","DepartureTime":"08:45"} ]} ]
    """
    private let liveBoard = #"[{"TrainNo":"100","DelayTime":0}]"#

    private func call(_ args: [String: Value]) async -> CallTool.Result {
        await TransitTools.handleCall(name: "transit_route", arguments: args,
                                      client: TestSupport.mockClient(), cache: Cache())
    }

    // (a) TRA→metro happy path: 中壢 → 西門 picks the 板橋 interchange (earliest).
    func testMultimodalHappyPath() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(metroS2S), d(metroFreq),
                                       d(metroLineTransfer), d(odTimetable), d(liveBoard)])
        let r = await call(["from": .string("中壢"), "to": .string("西門"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.count, 2)
        XCTAssertEqual(legs[0]["mode"] as? String, "TRA")
        XCTAssertEqual(legs[0]["from_station_id"] as? String, "1080")
        XCTAssertEqual(legs[0]["to_station_id"] as? String, "1020")
        XCTAssertEqual(legs[0]["source"] as? String, "live")
        XCTAssertEqual(legs[1]["mode"] as? String, "Metro")
        XCTAssertEqual(legs[1]["from_station_id"] as? String, "BL07")
        XCTAssertEqual(legs[1]["to_station_id"] as? String, "BL11")
        XCTAssertEqual(legs[1]["source"] as? String, "frequency")
        let transfers = try XCTUnwrap(o["transfers"] as? [[String: Any]])
        XCTAssertEqual(transfers.first?["at"] as? String, "1020")
        XCTAssertEqual(transfers.first?["walk_min"] as? Int, 4)
        XCTAssertEqual(o["arrival_time"] as? String, "08:43")
        XCTAssertEqual(o["transfer_count"] as? Int, 1)
    }

    // (b) Ambiguous endpoint → matches[], no route. Resolution short-circuits after the
    // two list fetches, so only token + traStations + metroSOR are consumed.
    func testAmbiguousEndpointReturnsMatches() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR)])
        let r = await call(["from": .string("山"), "to": .string("西門"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["ambiguous"] as? String, "from")
        let matches = try XCTUnwrap(o["matches"] as? [[String: Any]])
        XCTAssertEqual(matches.count, 2, "山 matches two distinct stations: 中山 + 松山")
        XCTAssertNil(o["legs"])
    }

    // (c) TRA timetable HTTP 500 → graceful empty routes + note (not an error).
    func testTRATimetableUnavailableGraceful() async throws {
        MockURLProtocol.stub = MockURLProtocol.Stub()
        func ok(_ data: Data) -> Result<(HTTPURLResponse, Data), Error> { .success((MockURLProtocol.httpResponse(200), data)) }
        MockURLProtocol.stub?.queuedResponses = [
            ok(TestSupport.tokenJSON()),
            ok(d(traStations)), ok(d(metroSOR)), ok(d(metroS2S)), ok(d(metroFreq)), ok(d(metroLineTransfer)),
            .success((MockURLProtocol.httpResponse(500), d("{}")))   // OD outage
        ]
        let r = await call(["from": .string("中壢"), "to": .string("西門"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false, "TDX outage is not our error")
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
    }

    // (d) Metro-only journey: 西門 → 市政府, no TRA fetch at all.
    func testMetroOnlyJourney() async throws {
        TestSupport.queueTokenThenAll([d(traStations), d(metroSOR), d(metroS2S), d(metroFreq), d(metroLineTransfer)])
        let r = await call(["from": .string("西門"), "to": .string("市政府"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let legs = try XCTUnwrap(o["legs"] as? [[String: Any]])
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs[0]["mode"] as? String, "Metro")
        XCTAssertEqual(legs[0]["from_station_id"] as? String, "BL11")
        XCTAssertEqual(legs[0]["to_station_id"] as? String, "BL18")
        XCTAssertEqual(o["arrival_time"] as? String, "08:05")   // 08:00 + wait 2 + ride 3
        XCTAssertEqual(o["transfer_count"] as? Int, 0)
    }
}
