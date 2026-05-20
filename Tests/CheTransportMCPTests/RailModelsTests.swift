// Tests/CheTransportMCPTests/RailModelsTests.swift
import XCTest
@testable import CheTransportMCP

final class RailModelsTests: XCTestCase {
    func testParseStations() throws {
        let url = Bundle.module.url(forResource: "rail_station", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let stations = try JSONDecoder().decode([RailStation].self, from: data)
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].stationID, "1000")
        XCTAssertEqual(stations[0].stationName.zhTw, "臺北")
    }

    func testParseTimetable() throws {
        let url = Bundle.module.url(forResource: "rail_timetable", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let trains = try JSONDecoder().decode([RailODFare].self, from: data)
        XCTAssertEqual(trains.count, 1)
        XCTAssertEqual(trains[0].trainInfo.trainNo, "152")
        XCTAssertEqual(trains[0].stopTimes.count, 2)
    }
}
