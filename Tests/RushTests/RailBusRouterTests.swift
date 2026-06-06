// Tests/RushTests/RailBusRouterTests.swift
import XCTest
@testable import Rush

/// Pure unit tests for Stage 3b rail→bus composition (#rail-bus-routing):
/// name-matching (incl. district-name reject) + earliest-arrival stitch.
final class RailBusRouterTests: XCTestCase {

    typealias RBR = RailBusRouter

    private func railLeg(arr: Int) -> MultimodalRouter.Leg {
        MultimodalRouter.Leg(mode: .tra, line: "1234", fromStation: "1000", fromName: "中壢",
                             toStation: "0980", toName: "臺北", depMin: 540, arrMin: arr,
                             delayMin: 2, source: "live")
    }

    private func busOpt(board: Int?, arr: Int?, boardStop: String = "捷運市政府站",
                        freqOnly: Bool = false) -> BusRouter.Option {
        BusRouter.Option(routeName: "266", subRouteName: "266", direction: 0,
                         boardStop: boardStop, alightStop: "迄站", boardInMin: board,
                         boardSource: freqOnly ? "frequency" : "scheduled",
                         arrivalClockMin: arr, arrivalTime: arr == nil ? nil : "HH:mm",
                         arrivalSource: arr == nil ? nil : "scheduled",
                         note: freqOnly ? "frequency-only：抵達時刻從缺" : nil)
    }

    // (a) name-match — patterns accept station stops, reject district-name lookalikes.
    func testNameMatchPatternsAndDistrictReject() {
        // metro 捷運X站
        XCTAssertTrue(RBR.busStopMatchesStation(stopName: "捷運市政府站", stationName: "市政府"))
        // TRA X車站 + 臺/台 normalization (station name 臺北, stop 臺北車站(忠孝))
        XCTAssertTrue(RBR.busStopMatchesStation(stopName: "臺北車站(忠孝)", stationName: "臺北"))
        // district-name station: accept the real 車站 stop…
        XCTAssertTrue(RBR.busStopMatchesStation(stopName: "南港行政中心(南港車站)", stationName: "南港"))
        // …reject the district lookalike (no station pattern)
        XCTAssertFalse(RBR.busStopMatchesStation(stopName: "南港高工", stationName: "南港"))
        XCTAssertFalse(RBR.busStopMatchesStation(stopName: "松山機場", stationName: "松山"))
        // station name already ending in 站 (metro 台北車站) → bare containment
        XCTAssertTrue(RBR.busStopMatchesStation(stopName: "臺北車站(忠孝)", stationName: "台北車站"))
        // empty station name never matches
        XCTAssertFalse(RBR.busStopMatchesStation(stopName: "任意站", stationName: ""))
    }

    // (b) stitch — board clock = nowMin + boardInMin (board already ≥ railArrival+walk upstream).
    func testStitchBoardClockArithmetic() {
        let now = 540                       // 09:00
        let opt = busOpt(board: 65, arr: 625)   // board 10:05
        let r = RBR.compose(railLegs: [railLeg(arr: 600)], transferStationName: "臺北",
                            transferWalkMin: 5, busOptions: [opt], nowMin: now)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.busBoardClockMin, now + 65)   // 605 = railArr 600 + walk 5
        XCTAssertEqual(r?.arrivalClockMin, 625)
        XCTAssertEqual(r?.railLegs.count, 1)
        XCTAssertEqual(r?.transferStationName, "臺北")
        XCTAssertEqual(r?.transferWalkMin, 5)
    }

    // (c) frequency-only bus → arrival null + note preserved.
    func testFrequencyOnlyArrivalOmitted() {
        let opt = busOpt(board: 70, arr: nil, freqOnly: true)
        let r = RBR.compose(railLegs: [railLeg(arr: 600)], transferStationName: "臺北",
                            transferWalkMin: 5, busOptions: [opt], nowMin: 540)
        XCTAssertNotNil(r)
        XCTAssertNil(r?.arrivalClockMin)
        XCTAssertNotNil(r?.bus.note)
    }

    // (d) multi-candidate → earliest known arrival wins; known beats unknown; tie → earlier board.
    func testEarliestArrivalSelection() {
        let now = 540
        let later   = busOpt(board: 60, arr: 620, boardStop: "捷運市政府站")
        let earlier = busOpt(board: 75, arr: 610, boardStop: "市政府站(松仁)")
        let unknown = busOpt(board: 50, arr: nil, boardStop: "其他", freqOnly: true)
        let r = RBR.compose(railLegs: [railLeg(arr: 600)], transferStationName: "市政府",
                            transferWalkMin: 5, busOptions: [later, earlier, unknown], nowMin: now)
        XCTAssertEqual(r?.arrivalClockMin, 610)            // earliest arrival, not earliest board
        XCTAssertEqual(r?.bus.boardStop, "市政府站(松仁)")

        // known (620) still beats unknown-arrival even though unknown boards sooner.
        let r2 = RBR.compose(railLegs: [railLeg(arr: 600)], transferStationName: "市政府",
                             transferWalkMin: 5, busOptions: [unknown, later], nowMin: now)
        XCTAssertEqual(r2?.arrivalClockMin, 620)

        // empty options → nil.
        XCTAssertNil(RBR.compose(railLegs: [railLeg(arr: 600)], transferStationName: "市政府",
                                 transferWalkMin: 5, busOptions: [], nowMin: now))
    }

    // MARK: - Stage 3b-ii: auto transfer-hub reverse search

    /// Build a BusStopOfRoute from a route id + ordered (uid, name) stop list.
    private func route(_ uid: String, dir: Int = 0, _ stops: [(String, String)]) -> BusStopOfRoute {
        let stopsJSON = stops.map { #"{"StopUID":"\#($0.0)","StopName":{"Zh_tw":"\#($0.1)"}}"# }.joined(separator: ",")
        let json = #"{"RouteUID":"\#(uid)","RouteName":{"Zh_tw":"\#(uid)"},"Direction":\#(dir),"Stops":[\#(stopsJSON)]}"#
        return try! JSONDecoder().decode(BusStopOfRoute.self, from: Data(json.utf8))
    }

    private let rail: [(id: String, name: String)] = [
        ("R1", "市政府"), ("R2", "忠孝復興"), ("R3", "南港"), ("R4", "松山")
    ]

    // (a) Only stops UPSTREAM of to_stop become candidates; downstream stops do not.
    func testCandidateHubsUpstreamOnly() {
        let r = route("299", [("M1", "捷運市政府站"), ("D1", "迄站"), ("F1", "捷運忠孝復興站")])
        let d = RBR.candidateHubs(toStopUID: "D1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.railStationName, "市政府")          // upstream M1
        XCTAssertFalse(d.hubs.contains { $0.railStationName == "忠孝復興" })  // downstream F1 excluded
    }

    // (b) District-name reject carries into the reverse search.
    func testCandidateHubsDistrictReject() {
        let r = route("市民小巴", [("G", "南港高工"), ("S", "南港行政中心(南港車站)"), ("D1", "迄站")])
        let d = RBR.candidateHubs(toStopUID: "D1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.boardingStopUID, "S")   // 南港車站 ✓, 南港高工 ✗
        XCTAssertEqual(d.hubs.first?.railStationName, "南港")
    }

    // (c) Same (hub, boarding stop) on two routes deduplicates to one candidate.
    func testCandidateHubsDedup() {
        let r1 = route("A", [("M1", "捷運市政府站"), ("D1", "迄站")])
        let r2 = route("B", [("M1", "捷運市政府站"), ("X", "別站"), ("D1", "迄站")])
        let d = RBR.candidateHubs(toStopUID: "D1", routes: [r1, r2], railStations: rail)
        XCTAssertEqual(d.hubs.count, 1)
        XCTAssertEqual(d.hubs.first?.boardingStopUID, "M1")
    }

    // (d) Cap truncates and reports the dropped count.
    func testCandidateHubsCapDisclosesDropped() {
        let r = route("multi", [("M1", "捷運市政府站"), ("M2", "捷運忠孝復興站"), ("M3", "南港車站"), ("D1", "迄站")])
        let d = RBR.candidateHubs(toStopUID: "D1", routes: [r], railStations: rail, cap: 2)
        XCTAssertEqual(d.hubs.count, 2)
        XCTAssertEqual(d.droppedCount, 1)   // 3 distinct candidates, cap 2
    }

    // (e) Closest-upstream candidate is ordered first (smallest index gap to to_stop).
    func testCandidateHubsProximityOrder() {
        // 松山(idx0, gap3) … 忠孝復興(idx1, gap2) … 市政府(idx2, gap1) … 迄站(idx3)
        let r = route("ord", [("F", "捷運松山站"), ("M", "捷運忠孝復興站"), ("N", "捷運市政府站"), ("D1", "迄站")])
        let d = RBR.candidateHubs(toStopUID: "D1", routes: [r], railStations: rail)
        XCTAssertEqual(d.hubs.first?.railStationName, "市政府")   // gap 1, closest
        XCTAssertEqual(d.hubs.last?.railStationName, "松山")      // gap 3, farthest
    }

    // (f) selectEarliest picks min final arrival across stitched hubs; known before unknown.
    func testSelectEarliestAcrossHubs() {
        func result(arr: Int?, board: Int) -> RBR.Result {
            RBR.Result(railLegs: [railLeg(arr: 600)], transferStationName: "X", transferWalkMin: 5,
                       bus: busOpt(board: board - 540, arr: arr), busBoardClockMin: board,
                       arrivalClockMin: arr)
        }
        let later = result(arr: 700, board: 650)
        let early = result(arr: 660, board: 655)
        let unknown = result(arr: nil, board: 610)
        XCTAssertEqual(RBR.selectEarliest([later, early, unknown])?.arrivalClockMin, 660)
        // known beats unknown even though unknown boards soonest.
        XCTAssertEqual(RBR.selectEarliest([unknown, later])?.arrivalClockMin, 700)
        XCTAssertNil(RBR.selectEarliest([]))
    }
}
