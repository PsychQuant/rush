import XCTest
@testable import CheTransportMCP

final class TrafficToolsTests: XCTestCase {
    func testDefineToolsReturnsThree() {
        let names = TrafficTools.defineTools().map(\.name)
        XCTAssertEqual(Set(names), Set([
            "traffic_freeway_live",
            "traffic_incidents",
            "traffic_cctv"
        ]))
    }

    func testFreewayLiveDecode() throws {
        let json = """
        [{
          "RoadID": "000010",
          "RoadName": "國道1號",
          "SectionID": "0001",
          "Direction": 0,
          "Speed": 78.5,
          "TravelTime": 120,
          "CongestionLevel": 2,
          "DataCollectTime": "2026-05-20T19:00:00+08:00"
        }]
        """
        let decoded = try JSONDecoder().decode([FreewayLive].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.roadID, "000010")
        XCTAssertEqual(decoded.first?.speed, 78.5)
        XCTAssertEqual(decoded.first?.congestionLevel, 2)
    }

    func testCCTVDecodeWithPosition() throws {
        let json = """
        [{
          "CCTVID": "CCTV-001",
          "RoadID": "000010",
          "LocationName": {"Zh_tw": "汐止系統交流道", "En": "Xizhi System IC"},
          "VideoStreamURL": "https://example.com/stream.m3u8",
          "ImageURL": "https://example.com/snapshot.jpg",
          "Position": {"PositionLat": 25.07, "PositionLon": 121.65}
        }]
        """
        let decoded = try JSONDecoder().decode([TrafficCCTV].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.cctvID, "CCTV-001")
        XCTAssertEqual(decoded.first?.position?.positionLat, 25.07)
        XCTAssertTrue(decoded.first?.videoStreamURL?.contains("m3u8") == true)
    }
}
