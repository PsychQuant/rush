import XCTest
@testable import Rush

final class ParkingToolsTests: XCTestCase {
    func testDefineToolsReturnsTwo() {
        let names = ParkingTools.defineTools().map(\.name)
        XCTAssertEqual(Set(names), Set(["parking_list_lots", "parking_status"]))
    }

    func testParseCityAccepts() throws {
        let city = try ParkingTools.parseCity(["city": .string("Taichung")])
        XCTAssertEqual(city, .Taichung)
    }

    func testParseCityRejectsUnknown() {
        do {
            _ = try ParkingTools.parseCity(["city": .string("Atlantis")])
            XCTFail("unknown city should throw")
        } catch let TDXError.decoding(msg) {
            XCTAssertTrue(msg.contains("Atlantis"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testParkingLotDecode() throws {
        let json = """
        [{
          "CarParkID": "TPE-0001",
          "CarParkName": {"Zh_tw": "市府轉運站停車場", "En": "City Hall Bus Terminal Parking"},
          "Address": "臺北市信義區忠孝東路五段",
          "TotalSpaces": 320,
          "CarParkType": 2,
          "CarParkPosition": {"PositionLat": 25.04, "PositionLon": 121.57}
        }]
        """
        let decoded = try JSONDecoder().decode([ParkingLot].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.carParkID, "TPE-0001")
        XCTAssertEqual(decoded.first?.totalSpaces, 320)
        XCTAssertEqual(decoded.first?.carParkPosition?.positionLat, 25.04)
    }
}
