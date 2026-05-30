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
        // Real TDX v2/Road/Traffic/Live/Freeway element shape (section-based).
        let json = """
        [{
          "SectionID": "0001",
          "TravelTime": 120,
          "TravelSpeed": 78.5,
          "CongestionLevelID": "2",
          "CongestionLevel": "車多",
          "DataCollectTime": "2026-05-20T19:00:00+08:00"
        }]
        """
        let decoded = try JSONDecoder().decode([FreewayLive].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.sectionID, "0001")
        XCTAssertEqual(decoded.first?.travelSpeed, 78.5)
        XCTAssertEqual(decoded.first?.congestionLevel, "車多")
    }

    func testCCTVDecodeWithPosition() throws {
        // Real TDX v2/Road/Traffic/CCTV/Highway element shape: top-level
        // coordinates + VideoImageURL (not a nested Position / ImageURL).
        let json = """
        [{
          "CCTVID": "CCTV-001",
          "RoadID": "000010",
          "RoadName": "國道1號",
          "VideoStreamURL": "https://example.com/stream.m3u8",
          "VideoImageURL": "https://example.com/snapshot.jpg",
          "PositionLon": 121.65,
          "PositionLat": 25.07,
          "SurveillanceDescription": "汐止系統交流道"
        }]
        """
        let decoded = try JSONDecoder().decode([TrafficCCTV].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.cctvID, "CCTV-001")
        XCTAssertEqual(decoded.first?.positionLat, 25.07)
        XCTAssertTrue(decoded.first?.videoStreamURL?.contains("m3u8") == true)
    }
}
