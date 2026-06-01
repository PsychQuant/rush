// Tests/CheTransportMCPTests/RailBusLiveTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Opt-in live check for `rail_bus_route` against the real TDX API (#rail-bus-routing).
/// Runs only when `TDX_CONTRACT` is set AND credentials resolve (env
/// `TDX_CLIENT_ID`/`TDX_CLIENT_SECRET` preferred, else keychain). Plain
/// `swift test` skips it.
///
/// Query: 中壢 → (transfer 臺北) → bus to 市政府. Live timetables + bus coverage +
/// service hours vary, so any of these is an accepted, non-error outcome: a stitched
/// rail→bus itinerary (rail legs + one bus leg), a `matches` disambiguation (popular
/// stop/station names map to several ids), or empty `routes` + note (rail unreachable
/// at this hour / no name-matched stop / no direct bus). The point is the executor
/// runs end-to-end against live TDX without erroring.
final class RailBusLiveTests: XCTestCase {

    private static func creds() throws -> (clientId: String, clientSecret: String) {
        let e = ProcessInfo.processInfo.environment
        if let id = e["TDX_CLIENT_ID"], let s = e["TDX_CLIENT_SECRET"], !id.isEmpty, !s.isEmpty {
            return (clientId: id, clientSecret: s)
        }
        return (clientId: try Auth.read(account: "client_id"),
                clientSecret: try Auth.read(account: "client_secret"))
    }

    func testRailBusRouteLive() async throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Live rail_bus_route check is opt-in. Set TDX_CONTRACT=1.")
        }
        let c: (clientId: String, clientSecret: String)
        do { c = try Self.creds() } catch { throw XCTSkip("TDX credentials unavailable.") }

        let client = TDXClient(credentialProvider: { c })
        let r = await TransitTools.handleCall(
            name: "rail_bus_route",
            arguments: ["from": .string("中壢"), "transfer": .string("臺北"),
                        "to_stop": .string("市政府"), "city": .string("Taipei")],
            client: client, cache: Cache())

        XCTAssertFalse(r.isError ?? false, "rail_bus_route must not surface a system error")
        let txt = TestSupport.textContent(r)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any])

        if let legs = o["legs"] as? [[String: Any]], !legs.isEmpty {
            print("LIVE rail_bus_route 中壢→臺北→市政府 → \(legs.count) legs:\n\(txt.prefix(700))")
            XCTAssertEqual(legs.last?["mode"] as? String, "Bus", "final leg must be the bus leg")
            XCTAssertEqual(o["transfer_count"] as? Int, 1)
            let busSource = legs.last?["source"] as? String
            XCTAssertTrue(["scheduled", "frequency", "unknown"].contains(busSource ?? ""),
                          "bus board source must be schedule/headway (A2 disabled post-transfer), got \(busSource ?? "nil")")
        } else if let matches = o["matches"] as? [[String: Any]] {
            print("LIVE rail_bus_route → ambiguous \(o["ambiguous"] ?? "endpoint"), \(matches.count) matches — executor + resolution OK")
            XCTAssertFalse(matches.isEmpty)
        } else {
            print("LIVE rail_bus_route → empty: \(o["note"] ?? o)")
            XCTAssertNotNil(o["note"], "empty routes must carry a note")
        }
    }

    /// Stage 3b-ii: same query with `transfer` OMITTED → auto-hub selection. to_stop is a
    /// concrete StopUID (捷運市政府站, TPE10767) so it resolves uniquely and drives the full
    /// reverse-search + per-hub stitch. Accepted outcomes: a stitched itinerary carrying
    /// `auto_selected_transfer`, a `matches` disambiguation, or empty + note.
    func testRailBusAutoHubLive() async throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Live rail_bus_route auto-hub check is opt-in. Set TDX_CONTRACT=1.")
        }
        let c: (clientId: String, clientSecret: String)
        do { c = try Self.creds() } catch { throw XCTSkip("TDX credentials unavailable.") }

        let client = TDXClient(credentialProvider: { c })
        let r = await TransitTools.handleCall(
            name: "rail_bus_route",
            arguments: ["from": .string("中壢"), "to_stop": .string("TPE10767"), "city": .string("Taipei")],
            client: client, cache: Cache())

        XCTAssertFalse(r.isError ?? false, "auto-hub rail_bus_route must not surface a system error")
        let txt = TestSupport.textContent(r)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any])

        if let legs = o["legs"] as? [[String: Any]], !legs.isEmpty {
            print("LIVE auto-hub 中壢→(auto)→TPE10767 → hub=\(o["auto_selected_transfer"] ?? "?"), \(legs.count) legs")
            XCTAssertNotNil(o["auto_selected_transfer"] as? String, "auto path must name the chosen hub")
            XCTAssertEqual(legs.last?["mode"] as? String, "Bus")
            XCTAssertEqual(o["transfer_count"] as? Int, 1)
        } else if let matches = o["matches"] as? [[String: Any]] {
            print("LIVE auto-hub → ambiguous, \(matches.count) matches — executor + resolution OK")
            XCTAssertFalse(matches.isEmpty)
        } else {
            print("LIVE auto-hub → empty: \(o["note"] ?? o)")
            XCTAssertNotNil(o["note"], "empty routes must carry a note")
        }
    }
}
