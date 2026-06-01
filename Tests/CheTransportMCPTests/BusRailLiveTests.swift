// Tests/CheTransportMCPTests/BusRailLiveTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Opt-in live check for `bus_rail_route` against the real TDX API (#bus-rail-routing).
/// Runs only when `TDX_CONTRACT` is set AND credentials resolve (env
/// `TDX_CLIENT_ID`/`TDX_CLIENT_SECRET` preferred, else keychain). Plain `swift test` skips it.
///
/// `transfer` omitted → auto alight-hub. `from_stop` is a concrete StopUID so it resolves
/// uniquely and drives the full forward-search + per-hub bus+rail stitch. Accepted, non-error
/// outcomes: a stitched bus→rail itinerary carrying `auto_selected_transfer`, a `matches`
/// disambiguation, or empty + note. The point is the executor runs end-to-end without erroring.
///
/// NOTE: this is TDX-call-heavy (forward search + up to 8 per-hub rail legs). Running it
/// back-to-back with RailBusLiveTests can trip the 50/min free-tier rate limit; live tests
/// are opt-in and NOT part of the offline gate.
final class BusRailLiveTests: XCTestCase {

    private static func creds() throws -> (clientId: String, clientSecret: String) {
        let e = ProcessInfo.processInfo.environment
        if let id = e["TDX_CLIENT_ID"], let s = e["TDX_CLIENT_SECRET"], !id.isEmpty, !s.isEmpty {
            return (clientId: id, clientSecret: s)
        }
        return (clientId: try Auth.read(account: "client_id"),
                clientSecret: try Auth.read(account: "client_secret"))
    }

    func testBusRailRouteAutoHubLive() async throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Live bus_rail_route check is opt-in. Set TDX_CONTRACT=1.")
        }
        let c: (clientId: String, clientSecret: String)
        do { c = try Self.creds() } catch { throw XCTSkip("TDX credentials unavailable.") }

        let client = TDXClient(credentialProvider: { c })
        // from_stop = 捷運市政府站 (TPE10767, unique StopUID); to = 板橋 (rail); transfer omitted.
        let r = await TransitTools.handleCall(
            name: "bus_rail_route",
            arguments: ["from_stop": .string("TPE10767"), "to": .string("板橋"), "city": .string("Taipei")],
            client: client, cache: Cache())

        XCTAssertFalse(r.isError ?? false, "bus_rail_route must not surface a system error")
        let txt = TestSupport.textContent(r)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any])

        if let legs = o["legs"] as? [[String: Any]], !legs.isEmpty {
            print("LIVE bus_rail_route TPE10767→(auto)→板橋 → hub=\(o["auto_selected_transfer"] ?? "?"), \(legs.count) legs")
            XCTAssertEqual(legs.first?["mode"] as? String, "Bus", "first leg must be the bus leg")
            XCTAssertNotNil(o["auto_selected_transfer"] as? String, "auto path must name the chosen hub")
            XCTAssertEqual(o["transfer_count"] as? Int, 1)
        } else if let matches = o["matches"] as? [[String: Any]] {
            print("LIVE bus_rail_route → ambiguous \(o["ambiguous"] ?? "endpoint"), \(matches.count) matches — executor + resolution OK")
            XCTAssertFalse(matches.isEmpty)
        } else {
            print("LIVE bus_rail_route → empty: \(o["note"] ?? o)")
            XCTAssertNotNil(o["note"], "empty routes must carry a note")
        }
    }
}
