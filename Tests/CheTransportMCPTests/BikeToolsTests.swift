import XCTest
@testable import CheTransportMCP

final class BikeToolsTests: XCTestCase {
    func testBikeCityCoversMajorCities() {
        XCTAssertTrue(BikeCity.allCases.count >= 13, "TDX YouBike data spans most counties")
        XCTAssertTrue(BikeCity.allCases.contains(.Taipei))
        XCTAssertTrue(BikeCity.allCases.contains(.Kaohsiung))
        XCTAssertTrue(BikeCity.allCases.contains(.Hsinchu))
    }

    func testServiceTypeParse() {
        XCTAssertEqual(BikeTools.parseServiceType("YouBike1.0"), .youBike1_0)
        XCTAssertEqual(BikeTools.parseServiceType("YouBike2.0"), .youBike2_0)
        XCTAssertNil(BikeTools.parseServiceType(nil), "nil means no filter")
        XCTAssertNil(BikeTools.parseServiceType("YouBike3.0"), "unknown version means no filter")
    }

    func testHaversineSelfDistanceZero() {
        let d = BikeTools.haversine(lat1: 25.0330, lon1: 121.5654, lat2: 25.0330, lon2: 121.5654)
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    func testHaversineTaipei101ToZhongxiaoFuxing() {
        // Taipei 101 ≈ (25.0339, 121.5645); Zhongxiao Fuxing MRT ≈ (25.0418, 121.5440)
        // Expected great-circle distance ≈ 2.2 km. Tolerance generous because both coords approximated.
        let d = BikeTools.haversine(lat1: 25.0339, lon1: 121.5645, lat2: 25.0418, lon2: 121.5440)
        XCTAssertEqual(d, 2200, accuracy: 300)
    }

    func testNameMatchTaiTaiNormalization() {
        let stationName = LocalizedName(zhTw: "臺大醫院", en: "NTU Hospital")
        XCTAssertTrue(BikeTools.matchesName(query: "台大", name: stationName), "台大 should match 臺大 via normalization")
    }

    func testDefineToolsReturnsThree() {
        let names = BikeTools.defineTools().map(\.name)
        XCTAssertEqual(Set(names), Set([
            "bike_search_stations",
            "bike_stations_nearby",
            "bike_status_station"
        ]))
    }

    func testParseCityRejectsUnknown() {
        do {
            _ = try BikeTools.parseCity(["city": .string("Atlantis")])
            XCTFail("unknown city should throw")
        } catch let TDXError.decoding(msg) {
            XCTAssertTrue(msg.contains("Atlantis"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
