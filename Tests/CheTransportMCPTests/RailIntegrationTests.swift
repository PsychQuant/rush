import XCTest
@testable import CheTransportMCP

final class RailIntegrationTests: XCTestCase {
    private func skipIfNoCredentials() throws {
        do {
            _ = try Auth.read(account: "client_id")
            _ = try Auth.read(account: "client_secret")
        } catch {
            throw XCTSkip("TDX credentials not in keychain. Run: make setup-tdx")
        }
    }

    func testListSystemsLocal() async {
        let systems = RailTools.listSystems()
        XCTAssertEqual(systems.count, 8, "Local sanity check, no credentials needed")
    }

    func testTRAStationFetchLive() async throws {
        try skipIfNoCredentials()
        let client = TDXClient()
        let cache = Cache()
        let data = try await client.fetch(
            path: "v3/Rail/TRA/Station",
            cacheTTL: 86400,
            cache: cache
        )
        XCTAssertGreaterThan(data.count, 100, "Expected non-trivial response")
        let stations = RailTools.decodeStationList(data: data)
        XCTAssertGreaterThan(stations.count, 100, "TRA has 200+ stations")
    }

    func testTHSRSearchTaipeiLive() async throws {
        try skipIfNoCredentials()
        let client = TDXClient()
        let cache = Cache()
        let data = try await client.fetch(
            path: "v3/Rail/THSR/Station",
            cacheTTL: 86400,
            cache: cache
        )
        let stations = RailTools.decodeStationList(data: data)
        let matches = RailTools.fuzzyMatch(query: "台北", in: stations)
        XCTAssertFalse(matches.isEmpty, "Should find Taipei THSR station")
    }
}
