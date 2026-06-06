// Tests/RushTests/BusRouteLiveTests.swift
import XCTest
import MCP
@testable import Rush

/// Opt-in live check for `bus_route` against the real TDX API (#bus-routing).
/// Runs only when `TDX_CONTRACT` is set AND credentials resolve (env
/// `TDX_CLIENT_ID`/`TDX_CLIENT_SECRET` preferred, else keychain). Plain
/// `swift test` skips it.
///
/// Bus data + service hours vary, so any of these is an accepted, non-error
/// outcome: a direct route with a live/scheduled/frequency board estimate, a
/// `matches` disambiguation (popular stop names map to many stop UIDs), or an
/// empty `routes` + note (no direct route). The point is that the executor runs
/// end-to-end against live TDX without erroring.
final class BusRouteLiveTests: XCTestCase {

    private static func creds() throws -> (clientId: String, clientSecret: String) {
        let e = ProcessInfo.processInfo.environment
        if let id = e["TDX_CLIENT_ID"], let s = e["TDX_CLIENT_SECRET"], !id.isEmpty, !s.isEmpty {
            return (clientId: id, clientSecret: s)
        }
        return (clientId: try Auth.read(account: "client_id"),
                clientSecret: try Auth.read(account: "client_secret"))
    }

    func testBusRouteLive() async throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Live bus check is opt-in. Set TDX_CONTRACT=1.")
        }
        let c: (clientId: String, clientSecret: String)
        do { c = try Self.creds() } catch { throw XCTSkip("TDX credentials unavailable.") }

        let client = TDXClient(credentialProvider: { c })
        let r = await BusTools.handleCall(
            name: "bus_route",
            arguments: ["from_stop": .string("臺北車站"), "to_stop": .string("市政府"), "city": .string("Taipei")],
            client: client, cache: Cache())

        XCTAssertFalse(r.isError ?? false, "bus_route must not surface a system error")
        let txt = TestSupport.textContent(r)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any])

        if let routes = o["routes"] as? [[String: Any]], !routes.isEmpty {
            print("LIVE bus_route 臺北車站→市政府 → \(routes.count) direct route(s):\n\(txt.prefix(600))")
            let sources = Set(routes.compactMap { $0["board_source"] as? String })
            XCTAssertTrue(sources.allSatisfy { ["live", "scheduled", "frequency", "unknown"].contains($0) })
        } else if let matches = o["matches"] as? [[String: Any]] {
            print("LIVE bus_route → ambiguous stop, \(matches.count) matches (popular name maps to many StopUIDs) — executor + resolution OK")
            XCTAssertFalse(matches.isEmpty)
        } else {
            print("LIVE bus_route → no direct route: \(o["note"] ?? o)")
            XCTAssertNotNil(o["note"], "empty routes must carry a note")
        }
    }
}
