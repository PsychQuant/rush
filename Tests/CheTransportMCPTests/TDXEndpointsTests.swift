import XCTest
@testable import CheTransportMCP

/// Pure (offline) tests for the endpoint registry. These lock in the #4 path
/// fixes and the registry's enumerable contract — no network required.
final class TDXEndpointsTests: XCTestCase {

    // MARK: - #4 regression: rail path conventions

    func testTRAStationPathUsesV3DatasetAfterSystem() {
        XCTAssertEqual(TDXEndpoints.railStation(.TRA), "v3/Rail/TRA/Station")
    }

    func testTHSRStationPathUsesV2NotV3() {
        // #4 root cause: THSR was wrongly on v3. TDX serves THSR under v2.
        XCTAssertEqual(TDXEndpoints.railStation(.THSR), "v2/Rail/THSR/Station")
    }

    func testMetroStationPathPutsDatasetBeforeOperator() {
        // Probe finding: v2/Rail/Metro/Station/{op} is 200; the old
        // v2/Rail/Metro/{op}/Station ordering was 404.
        XCTAssertEqual(TDXEndpoints.railStation(.TRTC), "v2/Rail/Metro/Station/TRTC")
        XCTAssertEqual(TDXEndpoints.railStation(.KRTC), "v2/Rail/Metro/Station/KRTC")
    }

    // MARK: - #5: metro O/D routing paths (dataset before operator)

    func testMetroRoutingPathsPutDatasetBeforeOperator() {
        // Live-probed 200 on TRTC; same operator-last-was-404 convention as the
        // metro Station endpoint, so dataset precedes the operator code.
        XCTAssertEqual(TDXEndpoints.metroStationOfRoute(.TRTC), "v2/Rail/Metro/StationOfRoute/TRTC")
        XCTAssertEqual(TDXEndpoints.metroS2STravelTime(.TRTC), "v2/Rail/Metro/S2STravelTime/TRTC")
        XCTAssertEqual(TDXEndpoints.metroFrequency(.KRTC), "v2/Rail/Metro/Frequency/KRTC")
        XCTAssertEqual(TDXEndpoints.metroLine(.TRTC), "v2/Rail/Metro/Line/TRTC")
        // #6: line-transfer endpoint, same dataset-before-operator convention.
        XCTAssertEqual(TDXEndpoints.metroLineTransfer(.TRTC), "v2/Rail/Metro/LineTransfer/TRTC")
    }

    func testMetroRoutingContractCasesAreEnumerated() {
        let keys = Set(TDXEndpoints.allContractCases.map(\.key))
        for expected in ["metro.TRTC.stationOfRoute", "metro.TRTC.s2sTravelTime",
                         "metro.TRTC.frequency", "metro.TRTC.line", "metro.TRTC.lineTransfer"] {
            XCTAssertTrue(keys.contains(expected), "missing metro contract case \(expected)")
        }
    }

    func testTHSRTimetableUsesDailyTimetableDatasetOnV2() {
        // #4: THSR uses DailyTimetable (not TRA's DailyTrainTimetable) on v2.
        XCTAssertEqual(
            TDXEndpoints.railTimetableOD(.THSR, from: "1000", to: "1070", date: "2026-05-30"),
            "v2/Rail/THSR/DailyTimetable/OD/1000/to/1070/2026-05-30"
        )
    }

    func testTRATimetableUsesDailyTrainTimetableDatasetOnV3() {
        XCTAssertEqual(
            TDXEndpoints.railTimetableOD(.TRA, from: "1000", to: "1070", date: "2026-05-30"),
            "v3/Rail/TRA/DailyTrainTimetable/OD/1000/to/1070/2026-05-30"
        )
    }

    // MARK: - Registry enumeration contract

    func testContractCaseCountMatchesExpected() {
        // 6 modes: rail 12 (8 station + 2 timetable + TRA trainLive + TRA stationLive;
        // THSR has no live board in TDX), air 2, bus 5, bike 2, traffic 3,
        // parking 2 = 26. Plus #5 metro O/D routing 4 (StationOfRoute,
        // S2STravelTime, Frequency, Line — one representative TRTC case each) = 30.
        // Plus #6 metro LineTransfer 1 (representative TRTC) = 31.
        // Plus Stage 3a bus Schedule 1 (representative) = 32.
        // (Maritime removed — no live API on the TDX platform.)
        XCTAssertEqual(TDXEndpoints.allContractCases.count, 32)
    }

    func testContractCaseKeysAreUnique() {
        let keys = TDXEndpoints.allContractCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "Duplicate contract-case keys: \(keys)")
    }

    func testEveryContractCaseHasNonEmptyConcretePath() {
        for c in TDXEndpoints.allContractCases {
            XCTAssertFalse(c.path.isEmpty, "Empty path for \(c.key)")
            XCTAssertFalse(c.path.contains("{"), "Unfilled template placeholder in \(c.key): \(c.path)")
        }
    }
}
