// Tests/CheTransportMCPTests/BusRouterTests.swift
import XCTest
@testable import CheTransportMCP

/// Pure unit tests for the direct-route bus assembly (#bus-routing). Synthetic
/// candidates + A2 + Bus/Schedule — exact board/arrival arithmetic.
final class BusRouterTests: XCTestCase {

    typealias BR = BusRouter

    private func cand(_ uid: String = "R1", dir: Int = 0, name: String = "671") -> BR.Candidate {
        BR.Candidate(routeUID: uid, routeName: name, subRouteName: name, direction: dir,
                     originStopUID: "S1", originStopName: "起站", destStopUID: "S2", destStopName: "迄站")
    }

    /// Timetable with one trip: S1 dep `oDep`, S2 arr `dArr` (seq 1 then 2 unless reversed).
    private func timetabled(_ uid: String = "R1", dir: Int = 0, oDep: String, dArr: String, reversed: Bool = false) -> BusSchedule {
        let oSeq = reversed ? 2 : 1, dSeq = reversed ? 1 : 2
        let trip = BusTimetable(tripID: "t1", serviceDay: nil, stopTimes: [
            BusScheduleStopTime(stopSequence: oSeq, stopUID: "S1", stopID: nil, arrivalTime: oDep, departureTime: oDep),
            BusScheduleStopTime(stopSequence: dSeq, stopUID: "S2", stopID: nil, arrivalTime: dArr, departureTime: dArr),
        ])
        return BusSchedule(routeUID: uid, routeName: LocalizedName(zhTw: "671", en: nil), subRouteUID: nil,
                           subRouteName: nil, direction: dir, frequencys: nil, timetables: [trip])
    }

    private func frequency(_ uid: String = "R1", dir: Int = 0, headway: Int = 8) -> BusSchedule {
        let band = BusFrequency(startTime: "06:00", endTime: "22:00", minHeadwayMins: headway, maxHeadwayMins: headway + 4, serviceDay: nil)
        return BusSchedule(routeUID: uid, routeName: LocalizedName(zhTw: "234", en: nil), subRouteUID: nil,
                           subRouteName: nil, direction: dir, frequencys: [band], timetables: nil)
    }

    // (a) Timetabled, no A2 → board = next scheduled departure; arrival = board + ride-time.
    func testTimetabledBoardAndArrival() {
        let opts = BR.route(candidates: [cand()], a2BySig: [:],
                            scheduleBySig: ["R1|0": timetabled(oDep: "08:10", dArr: "08:30")],
                            nowMin: 480, departAfterMin: 480, weekday: 2)
        XCTAssertEqual(opts.count, 1)
        XCTAssertEqual(opts[0].boardSource, "scheduled")
        XCTAssertEqual(opts[0].boardInMin, 10)          // 08:10 − 08:00
        XCTAssertEqual(opts[0].arrivalTime, "08:30")    // board 08:10 + 20 ride
        XCTAssertEqual(opts[0].arrivalSource, "scheduled")
    }

    // (b) Frequency-only → board = headway/2; arrival omitted + note.
    func testFrequencyBoardOnlyArrivalOmitted() {
        let opts = BR.route(candidates: [cand()], a2BySig: [:],
                            scheduleBySig: ["R1|0": frequency(headway: 8)],
                            nowMin: 480, departAfterMin: 480, weekday: 2)
        XCTAssertEqual(opts[0].boardSource, "frequency")
        XCTAssertEqual(opts[0].boardInMin, 4)           // 8/2
        XCTAssertNil(opts[0].arrivalTime)
        XCTAssertNotNil(opts[0].note)
    }

    // (c) A2 live present → board = live ETA (preferred over schedule); arrival = live board + ride-time.
    func testLiveETApreferredOverSchedule() {
        let opts = BR.route(candidates: [cand()], a2BySig: ["R1|0": 180],   // 3 min
                            scheduleBySig: ["R1|0": timetabled(oDep: "08:10", dArr: "08:30")],
                            nowMin: 480, departAfterMin: 480, weekday: 2)
        XCTAssertEqual(opts[0].boardSource, "live")
        XCTAssertEqual(opts[0].boardInMin, 3)
        XCTAssertEqual(opts[0].arrivalTime, "08:23")    // board 08:03 + 20 ride
    }

    // (d) Trip with dest BEFORE origin (wrong order) is ignored → arrival omitted; board falls to frequency.
    func testStopSequenceGuard() {
        var s = timetabled(oDep: "08:10", dArr: "08:30", reversed: true)   // S2 seq1, S1 seq2
        s = BusSchedule(routeUID: s.routeUID, routeName: s.routeName, subRouteUID: nil, subRouteName: nil,
                        direction: 0, frequencys: [BusFrequency(startTime: "06:00", endTime: "22:00",
                        minHeadwayMins: 10, maxHeadwayMins: 14, serviceDay: nil)], timetables: s.timetables)
        let opts = BR.route(candidates: [cand()], a2BySig: [:], scheduleBySig: ["R1|0": s],
                            nowMin: 480, departAfterMin: 480, weekday: 2)
        XCTAssertNil(opts[0].arrivalTime, "wrong-order trip must be ignored")
        XCTAssertEqual(opts[0].boardSource, "frequency") // falls back to headway
    }

    // (e) Sort: earliest arrival first; unknown-arrival (frequency) last.
    func testSortByEarliestArrival() {
        let opts = BR.route(
            candidates: [cand("R1", name: "A"), cand("R2", name: "B"), cand("R3", name: "C")],
            a2BySig: [:],
            scheduleBySig: [
                "R1|0": timetabled("R1", oDep: "08:10", dArr: "08:30"),  // arr 08:30
                "R2|0": timetabled("R2", oDep: "08:05", dArr: "08:20"),  // arr 08:20
                "R3|0": frequency("R3", headway: 6),                     // arr unknown
            ],
            nowMin: 480, departAfterMin: 480, weekday: 2)
        XCTAssertEqual(opts.map { $0.routeName }, ["B", "A", "C"])
    }
}
