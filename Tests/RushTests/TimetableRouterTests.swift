// Tests/RushTests/TimetableRouterTests.swift
import XCTest
@testable import Rush

/// Tests for the timetable earliest-arrival router (connection-scan label-setting)
/// and its live-delay adjustment. Trains come from the real-shaped wrapped OD
/// fixture (3 trains 1000→3300 at different times).
final class TimetableRouterTests: XCTestCase {

    private func trains() throws -> [RailODFare] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tra_timetable_od", withExtension: "json"))
        return TDXDecode.list(RailODFare.self, from: try Data(contentsOf: url))
    }
    private func m(_ hhmm: String) -> Int { TimetableRouter.minutesOfDay(hhmm)! }

    func testEarliestArrivalOnSchedule() throws {
        // No delays. depart_after 08:00 excludes train 300 (departs 07:30).
        // Earliest arrival among 100 (09:00) and 200 (09:05) is train 100.
        let conns = TimetableRouter.connections(from: try trains(), delays: [:])
        let it = TimetableRouter.earliestArrival(connections: conns, from: "1000", to: "3300", departAfterMin: m("08:00"))
        let route = try XCTUnwrap(it)
        XCTAssertEqual(route.legs.count, 1)
        XCTAssertEqual(route.legs[0].trainNo, "100")
        XCTAssertEqual(route.arrMin, m("09:00"))
        XCTAssertFalse(route.legs[0].live, "no delay data → scheduled")
    }

    func testNoReachableTrainReturnsNil() throws {
        let conns = TimetableRouter.connections(from: try trains(), delays: [:])
        XCTAssertNil(TimetableRouter.earliestArrival(connections: conns, from: "1000", to: "3300", departAfterMin: m("10:00")))
    }

    func testLiveDelayChangesChosenTrain() throws {
        // Spec Example: train 100 (08:00→09:00) runs +15 → live arrival 09:15;
        // train 200 (08:10→09:05) on time. So 200 now arrives earliest.
        let conns = TimetableRouter.connections(from: try trains(), delays: ["100": 15, "200": 0])
        let it = TimetableRouter.earliestArrival(connections: conns, from: "1000", to: "3300", departAfterMin: m("08:00"))
        let route = try XCTUnwrap(it)
        XCTAssertEqual(route.legs[0].trainNo, "200", "live delay on 100 makes on-time 200 the earliest arrival")
        XCTAssertEqual(route.arrMin, m("09:05"))
        XCTAssertTrue(route.legs[0].live, "200 had a live entry (delay 0) → live")
        XCTAssertEqual(route.legs[0].delayMin, 0)
    }

    // Security: depart_after is caller-supplied; an unbounded hour would overflow
    // `h * 60` and trap (crash). Out-of-range / overflow input must return nil.
    func testMinutesOfDayRejectsOverflowAndOutOfRange() {
        XCTAssertNil(TimetableRouter.minutesOfDay("200000000000000000:00"), "overflow input must not trap")
        XCTAssertNil(TimetableRouter.minutesOfDay("24:00"), "TRA times are 00:00–23:59")
        XCTAssertNil(TimetableRouter.minutesOfDay("25:00"))
        XCTAssertNil(TimetableRouter.minutesOfDay("08:60"))
        XCTAssertNil(TimetableRouter.minutesOfDay("-1:00"))
        XCTAssertNil(TimetableRouter.minutesOfDay("abc"))
        XCTAssertEqual(TimetableRouter.minutesOfDay("08:30"), 510)
        XCTAssertEqual(TimetableRouter.minutesOfDay("00:00"), 0)
        XCTAssertEqual(TimetableRouter.minutesOfDay("23:59"), 1439)
    }
}
