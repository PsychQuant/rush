// Tests/RushTests/RailModelsTests.swift
import XCTest
@testable import Rush

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

    // #6 Stage 1: DailyTrainTimetable OD arrives WRAPPED ({…,"TrainTimetables":[…]}),
    // not a bare array — TDXDecode.list must unwrap it into [RailODFare].
    func testParseTimetableODWrapped() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tra_timetable_od", withExtension: "json"))
        let trains = TDXDecode.list(RailODFare.self, from: try Data(contentsOf: url))
        XCTAssertEqual(trains.count, 3, "wrapped TrainTimetables must unwrap to 3 trains")
        let t100 = try XCTUnwrap(trains.first { $0.trainInfo.trainNo == "100" })
        XCTAssertEqual(t100.stopTimes.first?.stationID, "1000")
        XCTAssertEqual(t100.stopTimes.first?.departureTime, "08:00")
        XCTAssertEqual(t100.stopTimes.last?.stationID, "3300")
        XCTAssertEqual(t100.stopTimes.last?.arrivalTime, "09:00")
    }

    // TrainLiveBoard is likewise wrapped ({…,"TrainLiveBoards":[…]}).
    func testParseTrainLiveBoardWrapped() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tra_train_live_board", withExtension: "json"))
        let live = TDXDecode.list(RailLiveTrain.self, from: try Data(contentsOf: url))
        XCTAssertEqual(live.count, 2)
        let t100 = try XCTUnwrap(live.first { $0.trainNo == "100" })
        XCTAssertEqual(t100.delayTime, 15)
    }
}
