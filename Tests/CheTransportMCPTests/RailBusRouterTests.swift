// Tests/CheTransportMCPTests/RailBusRouterTests.swift
import XCTest
@testable import CheTransportMCP

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
}
