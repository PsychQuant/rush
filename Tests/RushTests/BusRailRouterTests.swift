// Tests/RushTests/BusRailRouterTests.swift
import XCTest
@testable import Rush

/// Pure unit tests for Stage 3c-i bus→rail composition (#bus-rail-routing):
/// forward (downstream) alight-hub discovery + earliest-rail-arrival selection.
final class BusRailRouterTests: XCTestCase {

    typealias BRR = BusRailRouter

    private func route(_ uid: String, dir: Int = 0, _ stops: [(String, String)]) -> BusStopOfRoute {
        let stopsJSON = stops.map { #"{"StopUID":"\#($0.0)","StopName":{"Zh_tw":"\#($0.1)"}}"# }.joined(separator: ",")
        let json = #"{"RouteUID":"\#(uid)","RouteName":{"Zh_tw":"\#(uid)"},"Direction":\#(dir),"Stops":[\#(stopsJSON)]}"#
        return try! JSONDecoder().decode(BusStopOfRoute.self, from: Data(json.utf8))
    }

    private let rail: [(id: String, name: String)] = [
        ("R1", "市政府"), ("R2", "忠孝復興"), ("R3", "南港"), ("R4", "松山")
    ]

    // (a) Only stops DOWNSTREAM of from_stop become candidates; upstream stops do not.
    func testCandidateAlightHubsDownstreamOnly() {
        // 捷運忠孝復興站(idx0, upstream) … from_stop(idx1) … 捷運市政府站(idx2, downstream)
        let r = route("299", [("U1", "捷運忠孝復興站"), ("F1", "起站"), ("M1", "捷運市政府站")])
        let d = BRR.candidateAlightHubs(fromStopUID: "F1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.railStationName, "市政府")          // downstream M1
        XCTAssertFalse(d.hubs.contains { $0.railStationName == "忠孝復興" })  // upstream U1 excluded
    }

    // (b) District-name reject carries into the forward search.
    func testCandidateAlightHubsDistrictReject() {
        let r = route("市民小巴", [("F1", "起站"), ("G", "南港高工"), ("S", "南港行政中心(南港車站)")])
        let d = BRR.candidateAlightHubs(fromStopUID: "F1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.alightStopUID, "S")    // 南港車站 ✓, 南港高工 ✗
        XCTAssertEqual(d.hubs.first?.railStationName, "南港")
    }

    // (c) Same (hub, alight stop) on two routes deduplicates to one candidate.
    func testCandidateAlightHubsDedup() {
        let r1 = route("A", [("F1", "起站"), ("M1", "捷運市政府站")])
        let r2 = route("B", [("F1", "起站"), ("X", "別站"), ("M1", "捷運市政府站")])
        let d = BRR.candidateAlightHubs(fromStopUID: "F1", routes: [r1, r2], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.alightStopUID, "M1")
    }

    // (d) Cap truncates and reports the dropped count.
    func testCandidateAlightHubsCapDisclosesDropped() {
        let r = route("multi", [("F1", "起站"), ("M1", "捷運市政府站"), ("M2", "捷運忠孝復興站"), ("M3", "南港車站")])
        let d = BRR.candidateAlightHubs(fromStopUID: "F1", routes: [r], railStations: rail, cap: 2)
        XCTAssertEqual(d.hubs.count, 2)
        XCTAssertEqual(d.droppedCount, 1)   // 3 distinct candidates, cap 2
    }

    // (e) Closest-downstream candidate is ordered first (smallest index gap to from_stop).
    func testCandidateAlightHubsProximityOrder() {
        // from(idx0) … 市政府(idx1, gap1) … 忠孝復興(idx2, gap2) … 松山(idx3, gap3)
        let r = route("ord", [("F1", "起站"), ("N", "捷運市政府站"), ("M", "捷運忠孝復興站"), ("S", "捷運松山站")])
        let d = BRR.candidateAlightHubs(fromStopUID: "F1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.first?.railStationName, "市政府")   // gap 1, closest
        XCTAssertEqual(d.hubs.last?.railStationName, "松山")      // gap 3, farthest
    }

    // (f) selectEarliest picks min final rail arrival across stitched hubs.
    func testSelectEarliestByRailArrival() {
        func result(railArr: Int, board: Int) -> BRR.Result {
            let opt = BusRouter.Option(routeName: "X", subRouteName: nil, direction: 0,
                                       boardStop: "起站", alightStop: "捷運站", boardInMin: board - 540,
                                       boardSource: "live", arrivalClockMin: nil, arrivalTime: nil,
                                       arrivalSource: nil, note: nil)
            let leg = MultimodalRouter.Leg(mode: .metro, line: "BL", fromStation: "BL1", fromName: "市政府",
                                           toStation: "BL2", toName: "南港", depMin: board, arrMin: railArr,
                                           delayMin: nil, source: "frequency")
            return BRR.compose(busOption: opt, busBoardClockMin: board, hubStationName: "市政府",
                               transferWalkMin: 5, railLegs: [leg], railArrMin: railArr)
        }
        let later = result(railArr: 700, board: 600)
        let early = result(railArr: 660, board: 610)
        XCTAssertEqual(BRR.selectEarliest([later, early])?.arrivalClockMin, 660)
        XCTAssertNil(BRR.selectEarliest([]))
    }
}
