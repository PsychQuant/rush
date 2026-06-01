// Tests/CheTransportMCPTests/TransitLiveTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Opt-in live check for `transit_route` against the real TDX API (#multimodal-routing).
/// Runs only when `TDX_CONTRACT` is set AND credentials resolve (env `TDX_CLIENT_ID`
/// / `TDX_CLIENT_SECRET` preferred, else keychain). Plain `swift test` skips it.
/// Both a real itinerary and a graceful "TRA timetable unavailable" note are accepted
/// — TDX's `DailyTrainTimetable` OD has intermittent outages and that degradation
/// path is itself a valid outcome.
final class TransitLiveTests: XCTestCase {

    private static func creds() throws -> (clientId: String, clientSecret: String) {
        let e = ProcessInfo.processInfo.environment
        if let id = e["TDX_CLIENT_ID"], let s = e["TDX_CLIENT_SECRET"], !id.isEmpty, !s.isEmpty {
            return (clientId: id, clientSecret: s)
        }
        return (clientId: try Auth.read(account: "client_id"),
                clientSecret: try Auth.read(account: "client_secret"))
    }

    func testTransitRouteLive() async throws {
        guard ProcessInfo.processInfo.environment["TDX_CONTRACT"] != nil else {
            throw XCTSkip("Live transit check is opt-in. Set TDX_CONTRACT=1.")
        }
        let c: (clientId: String, clientSecret: String)
        do { c = try Self.creds() } catch { throw XCTSkip("TDX credentials unavailable.") }

        let client = TDXClient(credentialProvider: { c })
        let r = await TransitTools.handleCall(
            name: "transit_route",
            arguments: ["from": .string("中壢"), "to": .string("西門"), "depart_after": .string("08:00")],
            client: client, cache: Cache())

        XCTAssertFalse(r.isError ?? false, "transit_route must not surface a system error")
        let txt = TestSupport.textContent(r)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any])

        if let legs = o["legs"] as? [[String: Any]], !legs.isEmpty {
            print("LIVE transit_route 中壢→西門 →\n\(txt)")
            XCTAssertNotNil(o["arrival_time"], "a real itinerary must carry arrival_time")
            XCTAssertNotNil(o["transfer_count"])
        } else {
            // Graceful degradation (TRA OD outage) or no curated path — acceptable.
            print("LIVE transit_route 中壢→西門 → graceful: \(o["note"] ?? o)")
            XCTAssertNotNil(o["note"], "no itinerary ⇒ a note must explain why")
        }
    }
}
