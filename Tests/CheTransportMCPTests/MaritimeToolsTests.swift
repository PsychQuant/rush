import XCTest
@testable import CheTransportMCP

final class MaritimeToolsTests: XCTestCase {
    func testDefineToolsReturnsTwo() {
        let names = MaritimeTools.defineTools().map(\.name)
        XCTAssertEqual(Set(names), Set([
            "maritime_list_routes",
            "maritime_status_schedule"
        ]))
    }

    func testDecodeMaritimeRouteShape() throws {
        // Minimal example from TDX response shape — verifies the Codable keys.
        let json = """
        [{
          "RouteID": "MTR001",
          "RouteName": {"Zh_tw": "台馬輪基隆-馬祖", "En": "Keelung-Matsu"},
          "OperatorID": "TWNC",
          "DepartureStopID": "KE001",
          "DestinationStopID": "MT001",
          "DepartureStopName": {"Zh_tw": "基隆", "En": "Keelung"},
          "DestinationStopName": {"Zh_tw": "馬祖", "En": "Matsu"}
        }]
        """
        let data = Data(json.utf8)
        let routes = try JSONDecoder().decode([MaritimeRoute].self, from: data)
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].routeID, "MTR001")
        XCTAssertEqual(routes[0].operatorID, "TWNC")
        XCTAssertEqual(routes[0].routeName?.zhTw, "台馬輪基隆-馬祖")
    }
}
