// Tests/RushTests/MultimodalRouterTests.swift
import XCTest
@testable import Rush

/// Unit tests for the multi-modal composition (#multimodal-routing). Synthetic
/// data only — a 3-station 板南線 (板橋 BL07 — 台北車站 BL12 — 西門 BL11) plus
/// hand-built TRA connections — so the earliest-arrival arithmetic is exact.
final class MultimodalRouterTests: XCTestCase {

    typealias MM = MultimodalRouter

    private var queryDate: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!   // Monday
    }

    /// `bands`: (startTime, endTime, minHeadway, maxHeadway). Default = all-day 4/6 min.
    private func metroData(bands: [(String, String, Int, Int)] = [("00:00", "24:00", 4, 6)]) -> MM.MetroData {
        let stations: [(String, String)] = [("BL07", "板橋"), ("BL12", "台北車站"), ("BL11", "西門")]
        let sor = MetroStationOfRoute(
            lineID: "BL", lineNo: nil, routeID: nil, direction: nil, lineName: nil, routeName: nil,
            stations: stations.enumerated().map {
                MetroRouteStation(sequence: $0.offset, stationID: $0.element.0,
                                  stationName: LocalizedName(zhTw: $0.element.1, en: nil))
            })
        let tts = [
            MetroTravelTime(sequence: 1, fromStationID: "BL07", toStationID: "BL12", runTime: 300, stopTime: 0), // 5 min
            MetroTravelTime(sequence: 2, fromStationID: "BL12", toStationID: "BL11", runTime: 120, stopTime: 0), // 2 min
        ]
        let s2s = MetroS2STravelTime(lineID: "BL", lineNo: nil, routeID: nil, travelTimes: tts)
        let sd = MetroServiceDay(serviceTag: nil, monday: true, tuesday: true, wednesday: true,
                                 thursday: true, friday: true, saturday: true, sunday: true, nationalHolidays: true)
        let heads = bands.map { MetroHeadway(peakFlag: nil, startTime: $0.0, endTime: $0.1,
                                             minHeadwayMins: $0.2, maxHeadwayMins: $0.3) }
        let freq = MetroFrequency(lineID: "BL", lineNo: nil, routeID: nil, serviceDay: sd,
                                  operationTime: nil, headways: heads)
        return MM.MetroData(stationOfRoute: [sor], s2s: [s2s], lineTransfer: [], frequency: [freq])
    }

    private func conn(_ train: String, _ from: String, _ fromN: String, _ to: String, _ toN: String,
                      _ dep: Int, _ arr: Int) -> TimetableRouter.Connection {
        TimetableRouter.Connection(trainNo: train, fromStation: from, fromName: fromN,
                                   toStation: to, toName: toN, depMin: dep, arrMin: arr, delayMin: 0, live: false)
    }

    // (a) TRA→metro composition picks the interchange giving the earliest arrival.
    func testPicksEarliestInterchange() {
        // X→台北(1000) arrives 530; X→板橋(1020=BL07) arrives 510.
        let conns = [conn("T1", "X", "桃園", "1000", "臺北", 480, 530),
                     conn("T2", "X", "桃園", "1020", "板橋", 480, 510)]
        let it = MM.route(from: MM.Stop(mode: .tra, ids: ["X"], name: "桃園"),
                          to: MM.Stop(mode: .metro, ids: ["BL11"], name: "西門"),
                          departAfterMin: 480, traConnections: conns, metro: metroData(), queryDate: queryDate)
        XCTAssertNotNil(it)
        // via 板橋: TRA arr 510 +walk4=514 +wait(4/2=2)=516, BL07→BL12 5 + BL12→BL11 2 = 523
        XCTAssertEqual(it?.arrMin, 523)
        XCTAssertEqual(it?.transfers.first?.at, "1020", "板橋 should win over 台北車站")
        XCTAssertEqual(it?.transferCount, 1)
        XCTAssertEqual(it?.legs.first?.mode, .tra)
        XCTAssertEqual(it?.legs.last?.mode, .metro)
        XCTAssertEqual(it?.legs.last?.toStation, "BL11")
        XCTAssertEqual(it?.legs.last?.source, "frequency")
    }

    // (b) Metro boarding adds expected wait = headway/2.
    func testExpectedWaitIsHeadwayHalf() {
        let from = MM.Stop(mode: .metro, ids: ["BL12"], name: "台北車站")
        let to = MM.Stop(mode: .metro, ids: ["BL11"], name: "西門")
        // headway 4 → wait 2 → 480 + 2 + 2(ride) = 484
        let fast = MM.route(from: from, to: to, departAfterMin: 480,
                            traConnections: [], metro: metroData(bands: [("00:00", "24:00", 4, 6)]), queryDate: queryDate)
        XCTAssertEqual(fast?.arrMin, 484)
        // headway 8 → wait 4 → 480 + 4 + 2 = 486
        let slow = MM.route(from: from, to: to, departAfterMin: 480,
                            traConnections: [], metro: metroData(bands: [("00:00", "24:00", 8, 10)]), queryDate: queryDate)
        XCTAssertEqual(slow?.arrMin, 486)
    }

    // (c) The headway band is selected at metro-entry time.
    func testEntryBandSelectsHeadway() {
        let from = MM.Stop(mode: .metro, ids: ["BL12"], name: "台北車站")
        let to = MM.Stop(mode: .metro, ids: ["BL11"], name: "西門")
        let twoBands: [(String, String, Int, Int)] = [("07:00", "09:00", 4, 6), ("09:00", "24:00", 10, 12)]
        let peak = MM.route(from: from, to: to, departAfterMin: 480, traConnections: [],   // 08:00 peak hw4 → wait2
                            metro: metroData(bands: twoBands), queryDate: queryDate)
        let off = MM.route(from: from, to: to, departAfterMin: 600, traConnections: [],    // 10:00 off-peak hw10 → wait5
                           metro: metroData(bands: twoBands), queryDate: queryDate)
        // ride time identical (2 min); only the entry wait differs (5 − 2 = 3).
        let peakWait = (peak!.arrMin - 480) - 2
        let offWait = (off!.arrMin - 600) - 2
        XCTAssertEqual(peakWait, 2)
        XCTAssertEqual(offWait, 5)
    }

    // (d) The interchange transfer carries the registry walk_min.
    func testTransferCarriesWalkMin() {
        let conns = [conn("T1", "X", "桃園", "1000", "臺北", 480, 520)]
        let it = MM.route(from: MM.Stop(mode: .tra, ids: ["X"], name: "桃園"),
                          to: MM.Stop(mode: .metro, ids: ["BL11"], name: "西門"),
                          departAfterMin: 480, traConnections: conns, metro: metroData(), queryDate: queryDate)
        XCTAssertEqual(it?.transfers.first?.at, "1000")
        XCTAssertEqual(it?.transfers.first?.atName, "台北車站")
        XCTAssertEqual(it?.transfers.first?.walkMin, 5, "台北車站 registry walk_min")
    }
}
