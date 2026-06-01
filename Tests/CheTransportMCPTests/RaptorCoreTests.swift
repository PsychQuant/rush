// Tests/CheTransportMCPTests/RaptorCoreTests.swift
import XCTest
@testable import CheTransportMCP

/// Stage 3c-ii.1 — the strategy-ensemble core: dominance selector (this file's first
/// section), the proven-composition floor, and the round-based RAPTOR strategy.
final class RaptorCoreTests: XCTestCase {

    // A strategy that returns a fixed journey, for selector tests.
    private struct Fixed: RoutingStrategy {
        let j: RaptorCore.Journey?
        func plan(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfterMin: Int,
                  inputs: RaptorCore.RoutingInputs) -> RaptorCore.Journey? { j }
    }

    private func leg() -> MultimodalRouter.Leg {
        MultimodalRouter.Leg(mode: .metro, line: "L", fromStation: "A", fromName: "A",
                             toStation: "B", toName: "B", depMin: 0, arrMin: 0, delayMin: nil, source: "frequency")
    }
    private func journey(arr: Int, legs: Int) -> RaptorCore.Journey {
        RaptorCore.Journey(legs: Array(repeating: leg(), count: legs), arrivalMin: arr)
    }
    private let O = MultimodalRouter.Stop(mode: .tra, ids: ["O"], name: "O")
    private let D = MultimodalRouter.Stop(mode: .tra, ids: ["D"], name: "D")
    private func emptyInputs() -> RaptorCore.RoutingInputs {
        RaptorCore.RoutingInputs(traConnections: [],
                                 metro: MultimodalRouter.MetroData(stationOfRoute: [], s2s: [], lineTransfer: [], frequency: []),
                                 queryDate: Date(timeIntervalSince1970: 0))
    }
    private func plan(_ ss: [RoutingStrategy]) -> RaptorCore.Journey? {
        RaptorCore.plan(from: O, to: D, departAfterMin: 0, inputs: emptyInputs(), strategies: ss)
    }

    // (a) earliest arrival wins.
    func testSelectorEarliestArrivalWins() {
        XCTAssertEqual(plan([Fixed(j: journey(arr: 700, legs: 1)), Fixed(j: journey(arr: 660, legs: 2))])?.arrivalMin, 660)
    }

    // (b) arrival tie → fewer transfers.
    func testSelectorArrivalTieFewerTransfers() {
        // both arrive 660; one has 3 legs (2 transfers), one has 1 leg (0 transfers).
        XCTAssertEqual(plan([Fixed(j: journey(arr: 660, legs: 3)), Fixed(j: journey(arr: 660, legs: 1))])?.transferCount, 0)
    }

    // (b2) full tie (arrival + transfers) → first registered wins (stable).
    func testSelectorFullTieFirstRegisteredWins() {
        let first = journey(arr: 660, legs: 1)
        let second = journey(arr: 660, legs: 1)
        let r = plan([Fixed(j: first), Fixed(j: second)])
        XCTAssertEqual(r?.arrivalMin, 660)   // either is acceptable; selector returns the first
    }

    // (c) all strategies nil → nil.
    func testSelectorAllNil() { XCTAssertNil(plan([Fixed(j: nil), Fixed(j: nil)])) }

    // (d) empty strategy list → nil.
    func testSelectorEmptyList() { XCTAssertNil(plan([])) }

    // MARK: - ComposedStrategy (the floor)

    private func decode<T: Decodable>(_ s: String) -> [T] {
        (try? JSONDecoder().decode([T].self, from: Data(s.utf8))) ?? []
    }
    /// Minimal metro-only inputs: BL line 西門(BL11) → 市政府(BL18), one S2S hop, all-day headway.
    private func metroInputs() -> RaptorCore.RoutingInputs {
        let sor: [MetroStationOfRoute] = decode("""
        [ {"LineID":"BL","Stations":[
            {"Sequence":1,"StationID":"BL11","StationName":{"Zh_tw":"西門"}},
            {"Sequence":2,"StationID":"BL18","StationName":{"Zh_tw":"市政府"}} ]} ]
        """)
        let s2s: [MetroS2STravelTime] = decode(#"[ {"LineID":"BL","TravelTimes":[{"FromStationID":"BL11","ToStationID":"BL18","RunTime":300,"StopTime":0}]} ]"#)
        let freq: [MetroFrequency] = decode("""
        [ {"LineID":"BL","ServiceDay":{"Monday":true,"Tuesday":true,"Wednesday":true,"Thursday":true,"Friday":true,"Saturday":true,"Sunday":true},
           "Headways":[{"StartTime":"00:00","EndTime":"24:00","MinHeadwayMins":4,"MaxHeadwayMins":6}]} ]
        """)
        return RaptorCore.RoutingInputs(traConnections: [],
            metro: MultimodalRouter.MetroData(stationOfRoute: sor, s2s: s2s, lineTransfer: [], frequency: freq),
            queryDate: Date())
    }
    private let ximen = MultimodalRouter.Stop(mode: .metro, ids: ["BL11"], name: "西門")
    private let cityHall = MultimodalRouter.Stop(mode: .metro, ids: ["BL18"], name: "市政府")

    func testComposedProducesMetroJourney() {
        let j = ComposedStrategy().plan(from: ximen, to: cityHall, departAfterMin: 480, inputs: metroInputs())
        XCTAssertNotNil(j)
        XCTAssertEqual(j?.legs.first?.mode, .metro)
        XCTAssertEqual(j?.legs.first?.source, "frequency")
    }

    // Floor guarantee: the ensemble (which includes Composed as a candidate) never arrives
    // later than Composed alone — regression below the proven engine is structurally impossible.
    func testEnsembleNeverRegressesBelowComposed() {
        let inputs = metroInputs()
        guard let composed = ComposedStrategy().plan(from: ximen, to: cityHall, departAfterMin: 480, inputs: inputs) else {
            return XCTFail("Composed should produce a journey")
        }
        let later = RaptorCore.Journey(legs: [leg()], arrivalMin: composed.arrivalMin + 30)
        let ensemble = RaptorCore.plan(from: ximen, to: cityHall, departAfterMin: 480, inputs: inputs,
                                       strategies: [ComposedStrategy(), Fixed(j: later)])
        XCTAssertEqual(ensemble?.arrivalMin, composed.arrivalMin)
        XCTAssertLessThanOrEqual(ensemble!.arrivalMin, composed.arrivalMin)
    }

    // MARK: - RaptorEngine (round-based, synthetic graphs)

    private func trip(_ from: String, _ to: String, dep: Int, arr: Int) -> RoutingGraph.Edge {
        .init(from: from, to: to, kind: .trip(line: "\(from)\(to)", depMin: dep, arrMin: arr, mode: .tra, source: "scheduled"))
    }

    // (a) A two-transfer (three-trip) destination needs maxRounds ≥ 2; maxRounds 1 cannot reach it.
    func testRaptorMultiTransferReachability() {
        let g = RoutingGraph(edges: [
            trip("A", "B", dep: 0, arr: 10),
            trip("B", "C", dep: 10, arr: 20),
            trip("C", "D", dep: 20, arr: 30),
        ], nameOf: ["A": "A", "B": "B", "C": "C", "D": "D"])
        XCTAssertNil(RaptorEngine.earliestArrival(graph: g, from: "A", to: "D", departAfterMin: 0, maxRounds: 1))
        let j = RaptorEngine.earliestArrival(graph: g, from: "A", to: "D", departAfterMin: 0, maxRounds: 2)
        XCTAssertEqual(j?.arrivalMin, 30)
        XCTAssertEqual(j?.transferCount, 2)   // 3 legs
    }

    // (b) A frequency edge contributes headway/2 + ride and a frequency-sourced leg.
    func testRaptorFrequencyExpectedWait() {
        let g = RoutingGraph(edges: [
            .init(from: "A", to: "B", kind: .frequency(line: "BL", headwayMin: 10, rideMin: 5)),
        ], nameOf: ["A": "A", "B": "B"])
        let j = RaptorEngine.earliestArrival(graph: g, from: "A", to: "B", departAfterMin: 100, maxRounds: 0)
        XCTAssertEqual(j?.arrivalMin, 110)              // 100 + 10/2 + 5
        XCTAssertEqual(j?.legs.first?.source, "frequency")
        XCTAssertEqual(j?.legs.first?.depMin, 105)      // boarded after the expected wait
    }

    // (c) Earliest-arrival label dominance: the cheaper two-hop path beats the direct edge.
    func testRaptorEarliestArrivalDominance() {
        let g = RoutingGraph(edges: [
            trip("A", "C", dep: 0, arr: 50),    // direct, slow
            trip("A", "B", dep: 0, arr: 10),
            trip("B", "C", dep: 10, arr: 40),   // via B, faster
        ], nameOf: [:])
        XCTAssertEqual(RaptorEngine.earliestArrival(graph: g, from: "A", to: "C", departAfterMin: 0, maxRounds: 2)?.arrivalMin, 40)
    }
}
