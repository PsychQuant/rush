// Tests/CheTransportMCPTests/RaptorTransitEquivalenceTests.swift
import XCTest
@testable import CheTransportMCP

/// The differential oracle (Stage 3c-ii.1): replay `transit_route`'s journeys through the
/// strategy ensemble and assert the selected journey matches. `transit_route` delegates to
/// `MultimodalRouter.route`, which `ComposedStrategy` reproduces — so the ensemble (Composed
/// floor + Raptor candidate) returns the same journey: Composed wins ties (registered first)
/// and Raptor never under-counts. Equivalence is by construction; this proves it on fixtures.
final class RaptorTransitEquivalenceTests: XCTestCase {

    private func decode<T: Decodable>(_ s: String) -> [T] {
        (try? JSONDecoder().decode([T].self, from: Data(s.utf8))) ?? []
    }
    private func traConns(_ odJSON: String) -> [TimetableRouter.Connection] {
        TimetableRouter.connections(from: decode(odJSON) as [RailODFare], delays: [:])
    }
    private func metroData(sor: String, s2s: String, freq: String, lt: String = "[]") -> MultimodalRouter.MetroData {
        MultimodalRouter.MetroData(stationOfRoute: decode(sor), s2s: decode(s2s),
                                   lineTransfer: decode(lt), frequency: decode(freq))
    }
    private let queryDate = Date(timeIntervalSince1970: 0)   // all-day band + all-true serviceDay → any date

    /// Run both the proven composition and the ensemble; assert the ensemble reproduces it.
    private func assertEquivalent(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfter: Int,
                                  inputs: RaptorCore.RoutingInputs, file: StaticString = #filePath, line: UInt = #line) {
        let composed = MultimodalRouter.route(from: from, to: to, departAfterMin: departAfter,
                                              traConnections: inputs.traConnections, metro: inputs.metro, queryDate: inputs.queryDate)
        let ensemble = RaptorCore.plan(from: from, to: to, departAfterMin: departAfter, inputs: inputs,
                                       strategies: [ComposedStrategy(), RaptorStrategy()])
        guard let c = composed else { XCTAssertNil(ensemble, "ensemble should be empty when transit_route is", file: file, line: line); return }
        guard let e = ensemble else { XCTFail("ensemble nil but transit_route returned a journey", file: file, line: line); return }
        XCTAssertEqual(e.arrivalMin, c.arrMin, "arrival", file: file, line: line)
        XCTAssertEqual(e.transferCount, c.transferCount, "transfer_count", file: file, line: line)
        XCTAssertEqual(e.legs.count, c.legs.count, "leg count", file: file, line: line)
        for (a, b) in zip(e.legs, c.legs) {
            XCTAssertEqual(a.mode, b.mode, "leg mode", file: file, line: line)
            XCTAssertEqual(a.fromStation, b.fromStation, "leg from", file: file, line: line)
            XCTAssertEqual(a.toStation, b.toStation, "leg to", file: file, line: line)
            XCTAssertEqual(a.source, b.source, "leg source", file: file, line: line)
        }
    }

    // Fixtures mirror TransitToolsTests (the transit_route executor fixtures).
    private let odTimetable = """
    [ {"TrainInfo":{"TrainNo":"100","TrainTypeName":{"Zh_tw":"自強"}},
       "StopTimes":[
        {"StationID":"1080","StationName":{"Zh_tw":"中壢"},"ArrivalTime":"08:00","DepartureTime":"08:00"},
        {"StationID":"1020","StationName":{"Zh_tw":"板橋"},"ArrivalTime":"08:30","DepartureTime":"08:31"},
        {"StationID":"1000","StationName":{"Zh_tw":"臺北"},"ArrivalTime":"08:45","DepartureTime":"08:45"} ]} ]
    """
    private let metroSOR = """
    [ {"LineID":"BL","Stations":[
        {"Sequence":1,"StationID":"BL07","StationName":{"Zh_tw":"板橋"}},
        {"Sequence":2,"StationID":"BL12","StationName":{"Zh_tw":"台北車站"}},
        {"Sequence":3,"StationID":"BL11","StationName":{"Zh_tw":"西門"}},
        {"Sequence":4,"StationID":"BL18","StationName":{"Zh_tw":"市政府"}} ]} ]
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
    private func inputs() -> RaptorCore.RoutingInputs {
        RaptorCore.RoutingInputs(traConnections: traConns(odTimetable),
            metro: metroData(sor: metroSOR, s2s: metroS2S, freq: metroFreq), queryDate: queryDate)
    }
    private func stop(_ mode: MultimodalRouter.Mode, _ ids: [String], _ name: String) -> MultimodalRouter.Stop {
        MultimodalRouter.Stop(mode: mode, ids: ids, name: name)
    }

    // (1) TRA→metro: 中壢 → 西門 via the 板橋 interchange.
    func testEquivalentTRAtoMetro() {
        assertEquivalent(from: stop(.tra, ["1080"], "中壢"), to: stop(.metro, ["BL11"], "西門"),
                         departAfter: 480, inputs: inputs())
    }

    // (2) metro-only: 西門 → 市政府.
    func testEquivalentMetroOnly() {
        assertEquivalent(from: stop(.metro, ["BL11"], "西門"), to: stop(.metro, ["BL18"], "市政府"),
                         departAfter: 480, inputs: inputs())
    }

    // (3) TRA-only: 中壢 → 臺北 (Composed merges to one leg; the ensemble's fewer-transfers tiebreak keeps it).
    func testEquivalentTRAOnly() {
        assertEquivalent(from: stop(.tra, ["1080"], "中壢"), to: stop(.tra, ["1000"], "臺北"),
                         departAfter: 480, inputs: inputs())
    }

    // (4) Unreachable: a metro destination with no path → both empty.
    func testEquivalentUnreachable() {
        // 西門 → an isolated node not on any S2S edge → no metro path.
        assertEquivalent(from: stop(.metro, ["BL11"], "西門"), to: stop(.metro, ["ZZ99"], "孤島"),
                         departAfter: 480, inputs: inputs())
    }
}
