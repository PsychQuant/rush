// Tests/CheTransportMCPTests/MetroModelsTests.swift
import XCTest
@testable import CheTransportMCP

/// Offline decode tests for the metro routing models, driven by fixtures whose
/// shapes were captured live from TDX `v2/Rail/Metro/{Dataset}/TRTC` (板南線).
final class MetroModelsTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    func testParseStationOfRoute() throws {
        let routes = try JSONDecoder().decode([MetroStationOfRoute].self, from: fixture("metro_station_of_route"))
        XCTAssertEqual(routes.count, 2)
        let fwd = try XCTUnwrap(routes.first { $0.routeID == "BL-1" })
        XCTAssertEqual(fwd.lineID, "BL")
        XCTAssertEqual(fwd.direction, 0)
        XCTAssertEqual(fwd.stations.count, 4)
        XCTAssertEqual(fwd.stations.first?.stationID, "BL01")
        XCTAssertEqual(fwd.stations.first?.sequence, 1)
        XCTAssertEqual(fwd.stations.last?.stationName.zhTw, "南港")
    }

    func testParseS2STravelTime() throws {
        let segments = try JSONDecoder().decode([MetroS2STravelTime].self, from: fixture("metro_s2s_travel_time"))
        XCTAssertEqual(segments.count, 1)
        let bl1 = try XCTUnwrap(segments.first)
        XCTAssertEqual(bl1.routeID, "BL-1")
        XCTAssertEqual(bl1.travelTimes.count, 3)
        XCTAssertEqual(bl1.travelTimes[0].fromStationID, "BL01")
        XCTAssertEqual(bl1.travelTimes[0].toStationID, "BL02")
        XCTAssertEqual(bl1.travelTimes[0].runTime, 120)
        XCTAssertEqual(bl1.travelTimes[0].stopTime, 30)
    }

    func testParseFrequency() throws {
        let freqs = try JSONDecoder().decode([MetroFrequency].self, from: fixture("metro_frequency"))
        XCTAssertEqual(freqs.count, 2)
        let weekday = try XCTUnwrap(freqs.first { $0.serviceDay.monday })
        XCTAssertEqual(weekday.routeID, "BL-1")
        XCTAssertEqual(weekday.serviceDay.serviceTag, "平日")
        XCTAssertFalse(weekday.serviceDay.saturday)
        XCTAssertEqual(weekday.headways.count, 3)
        let peak = try XCTUnwrap(weekday.headways.first { $0.startTime == "07:00" })
        XCTAssertEqual(peak.minHeadwayMins, 6)
    }

    func testParseLine() throws {
        let lines = try JSONDecoder().decode([MetroLine].self, from: fixture("metro_line"))
        XCTAssertEqual(lines.count, 1)
        let bl = try XCTUnwrap(lines.first)
        XCTAssertEqual(bl.lineID, "BL")
        XCTAssertEqual(bl.lineName?.zhTw, "板南線")
        XCTAssertEqual(bl.lineColor, "#0a59ae")
    }

    func testParseLineTransfer() throws {
        let transfers = try JSONDecoder().decode([MetroLineTransfer].self, from: fixture("metro_line_transfer"))
        XCTAssertEqual(transfers.count, 2)
        let taipeiMain = try XCTUnwrap(transfers.first { $0.fromStationID == "BL12" })
        XCTAssertEqual(taipeiMain.fromLineID, "BL")
        XCTAssertEqual(taipeiMain.toLineID, "R")
        XCTAssertEqual(taipeiMain.toStationID, "R10")
        XCTAssertEqual(taipeiMain.transferTime, 4)
        XCTAssertEqual(taipeiMain.isOnSiteTransfer, 1)
    }
}
