// Tests/CheTransportMCPTests/BusRouteToolTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Executor tests for `bus_route` (#bus-routing). Inline FIFO fixtures drive the
/// fetch order: busStop (resolve) → StopOfRoute (candidates) → A2 (board) → Schedule.
/// Time-dependent values (exact board_in_min) come from `Date()`, so these assert
/// structure + source labels; exact arithmetic is covered by `BusRouterTests`.
final class BusRouteToolTests: XCTestCase {

    override func setUp() { super.setUp(); MockURLProtocol.stub = MockURLProtocol.Stub() }
    override func tearDown() { MockURLProtocol.stub = nil; super.tearDown() }

    private func d(_ s: String) -> Data { Data(s.utf8) }
    private func parse(_ r: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TestSupport.textContent(r).utf8)) as? [String: Any])
    }
    private func call(_ args: [String: Value]) async -> CallTool.Result {
        await BusTools.handleCall(name: "bus_route", arguments: args, client: TestSupport.mockClient(), cache: Cache())
    }

    private let busStops = """
    [ {"StopUID":"S1","StopName":{"Zh_tw":"起站"}},
      {"StopUID":"S2","StopName":{"Zh_tw":"迄站"}},
      {"StopUID":"S3","StopName":{"Zh_tw":"孤站"}},
      {"StopUID":"M1","StopName":{"Zh_tw":"市政府"}},
      {"StopUID":"M2","StopName":{"Zh_tw":"市政府"}} ]
    """
    private let stopOfRoute = """
    [ {"RouteUID":"671","RouteName":{"Zh_tw":"671"},"Direction":0,"Stops":[
        {"StopUID":"S1","StopName":{"Zh_tw":"起站"}},
        {"StopUID":"S2","StopName":{"Zh_tw":"迄站"}} ]} ]
    """
    private let a2 = #"[{"StopUID":"S1","RouteUID":"671","RouteName":{"Zh_tw":"671"},"Direction":0,"EstimateTime":120,"StopStatus":0}]"#
    private let schedule = """
    [ {"RouteUID":"671","RouteName":{"Zh_tw":"671"},"Direction":0,"Timetables":[
        {"TripID":"t1","StopTimes":[
          {"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:10","DepartureTime":"08:10"},
          {"StopSequence":2,"StopUID":"S2","ArrivalTime":"08:30","DepartureTime":"08:30"} ]} ]} ]
    """

    // (a) Happy path: direct route 671, A2 live board + timetabled arrival.
    func testDirectRouteHappyPath() async throws {
        TestSupport.queueTokenThenAll([d(busStops), d(stopOfRoute), d(a2), d(schedule)])
        let r = await call(["from_stop": .string("起站"), "to_stop": .string("迄站"), "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let routes = try XCTUnwrap(o["routes"] as? [[String: Any]])
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0]["route_name"] as? String, "671")
        XCTAssertEqual(routes[0]["board_source"] as? String, "live")   // A2 present
        XCTAssertNotNil(routes[0]["arrival_time"] as? String)          // timetabled
        XCTAssertEqual(routes[0]["arrival_source"] as? String, "scheduled")
    }

    // (b) Ambiguous stop → matches, no routes. Short-circuits after the busStop fetch.
    func testAmbiguousStopReturnsMatches() async throws {
        TestSupport.queueTokenThenAll([d(busStops)])
        let r = await call(["from_stop": .string("市政府"), "to_stop": .string("迄站"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual(o["ambiguous"] as? String, "from_stop")
        XCTAssertEqual((o["matches"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(o["routes"])
    }

    // (c) No direct route → empty + note (transfers not yet supported).
    func testNoDirectRouteEmptyWithNote() async throws {
        TestSupport.queueTokenThenAll([d(busStops), d(stopOfRoute)])
        let r = await call(["from_stop": .string("起站"), "to_stop": .string("孤站"), "city": .string("Taipei")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        XCTAssertEqual((o["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(o["note"])
    }

    // (d) A2 unavailable (empty) → board falls back to schedule, no error.
    func testA2MissingGracefulFallback() async throws {
        TestSupport.queueTokenThenAll([d(busStops), d(stopOfRoute), d("[]"), d(schedule)])
        let r = await call(["from_stop": .string("起站"), "to_stop": .string("迄站"), "city": .string("Taipei"), "depart_after": .string("08:00")])
        XCTAssertFalse(r.isError ?? false)
        let o = try parse(r)
        let routes = try XCTUnwrap(o["routes"] as? [[String: Any]])
        XCTAssertEqual(routes[0]["board_source"] as? String, "scheduled")  // no A2 → next timetabled departure
        XCTAssertNotNil(routes[0]["arrival_time"] as? String)
    }
}
