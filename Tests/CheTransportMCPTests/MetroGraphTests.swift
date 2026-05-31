// Tests/CheTransportMCPTests/MetroGraphTests.swift
import XCTest
@testable import CheTransportMCP

/// Unit tests for the routing graph + shortest-path search, on small synthetic
/// networks. Nodes are line-prefixed station IDs; ride edges come from
/// StationOfRoute adjacency weighted by S2STravelTime; transfer edges come from
/// LineTransfer weighted by walk + headway/2.
final class MetroGraphTests: XCTestCase {

    // MARK: - builders (terse synthetic-network construction)

    private func nm(_ s: String) -> LocalizedName { LocalizedName(zhTw: s, en: s) }

    private func route(_ line: String, _ id: String, _ ids: [String]) -> MetroStationOfRoute {
        MetroStationOfRoute(
            lineID: line, lineNo: line, routeID: id, direction: 0, lineName: nil, routeName: nil,
            stations: ids.enumerated().map { MetroRouteStation(sequence: $0.offset + 1, stationID: $0.element, stationName: nm($0.element)) })
    }

    /// `pairs` are (from, to, runTimeSeconds); stopTime is 0 for these tests.
    private func s2s(_ line: String, _ id: String, _ pairs: [(String, String, Int)]) -> MetroS2STravelTime {
        MetroS2STravelTime(lineID: line, lineNo: line, routeID: id,
            travelTimes: pairs.map { MetroTravelTime(sequence: nil, fromStationID: $0.0, toStationID: $0.1, runTime: $0.2, stopTime: 0) })
    }

    private func xfer(_ fl: String, _ fs: String, _ tl: String, _ ts: String, _ minutes: Int) -> MetroLineTransfer {
        MetroLineTransfer(fromLineID: fl, fromStationID: fs, fromStationName: nm(fs),
            toLineID: tl, toStationID: ts, toStationName: nm(ts),
            isOnSiteTransfer: 0, transferTime: minutes, transferDescription: nil)
    }

    // MARK: - tests

    func testShortestPathSameLine() {
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2", "A3"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 60), ("A2", "A3", 60)])],
            lineTransfer: [], headwayByLine: ["A": 8])
        let p = g.shortestPathByTime(from: "A1", to: "A3")
        XCTAssertEqual(p?.stations, ["A1", "A2", "A3"])
        XCTAssertEqual(p?.transferCount, 0)
    }

    func testTransferPath() {
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2"]), route("B", "B-1", ["B1", "B2"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 60)]), s2s("B", "B-1", [("B1", "B2", 60)])],
            lineTransfer: [xfer("A", "A2", "B", "B1", 2)], headwayByLine: ["A": 8, "B": 8])
        let p = g.shortestPathByTime(from: "A1", to: "B2")
        XCTAssertEqual(p?.transferCount, 1)
        XCTAssertEqual(p?.stations, ["A1", "A2", "B1", "B2"])
    }

    func testCircularShortcutBeatsLongDirect() {
        // Direct line A: A1..A5, each hop 2 min → 8 min, 0 transfers.
        // Shortcut line C: transfer A1↔C1 (1 min) + C1→C2 ride (1 min) + transfer C2↔A5 (1 min).
        // With small headway (wait≈1), via-C ≈ 5 min < 8 min → shortest path takes the shortcut.
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2", "A3", "A4", "A5"]), route("C", "C-1", ["C1", "C2"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 120), ("A2", "A3", 120), ("A3", "A4", 120), ("A4", "A5", 120)]),
                  s2s("C", "C-1", [("C1", "C2", 60)])],
            lineTransfer: [xfer("A", "A1", "C", "C1", 1), xfer("C", "C2", "A", "A5", 1)],
            headwayByLine: ["A": 2, "C": 2])
        let p = g.shortestPathByTime(from: "A1", to: "A5")
        XCTAssertEqual(p?.transferCount, 2, "the 2-transfer C shortcut is faster than the 8-min direct ride")
        XCTAssertTrue(p?.stations.contains("C1") ?? false)
    }

    func testSingleLineSystemGraceful() {
        // No transfer data (single-line system) — same-line routing still works.
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2", "A3"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 60), ("A2", "A3", 60)])],
            lineTransfer: [], headwayByLine: ["A": 8])
        XCTAssertNotNil(g.shortestPathByTime(from: "A1", to: "A3"))
    }

    func testUnreachableReturnsNil() {
        // Two disconnected lines, no transfer edge → no path.
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2"]), route("B", "B-1", ["B1", "B2"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 60)]), s2s("B", "B-1", [("B1", "B2", 60)])],
            lineTransfer: [], headwayByLine: [:])
        XCTAssertNil(g.shortestPathByTime(from: "A1", to: "B2"))
    }

    func testFewestTransfersPrefersZeroTransfer() {
        let g = MetroGraph(
            stationOfRoute: [route("A", "A-1", ["A1", "A2", "A3"])],
            s2s: [s2s("A", "A-1", [("A1", "A2", 60), ("A2", "A3", 60)])],
            lineTransfer: [], headwayByLine: ["A": 8])
        XCTAssertEqual(g.shortestPathByTransfers(from: "A1", to: "A3")?.transferCount, 0)
    }
}
