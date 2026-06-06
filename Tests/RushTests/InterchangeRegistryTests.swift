// Tests/RushTests/InterchangeRegistryTests.swift
import XCTest
@testable import Rush

/// Sanity coverage for the curated TRA↔TRTC interchange table (#multimodal-routing).
/// These pin the registry's shape — every entry must be usable as a real transfer
/// (TRA id + ≥1 TRTC id + a plausible walk time) and lookups must be bidirectional.
final class InterchangeRegistryTests: XCTestCase {

    func testEntriesAreWellFormed() {
        XCTAssertFalse(InterchangeRegistry.entries.isEmpty, "registry must not be empty")
        for e in InterchangeRegistry.entries {
            XCTAssertFalse(e.traStationID.isEmpty, "\(e.name) missing TRA station id")
            XCTAssertFalse(e.trtcStationIDs.isEmpty, "\(e.name) has no TRTC station ids")
            XCTAssertTrue((1...30).contains(e.walkMin), "\(e.name) walk_min \(e.walkMin) out of plausible range")
        }
    }

    func testBidirectionalLookup() {
        let taipei = InterchangeRegistry.byTRA("1000")
        XCTAssertEqual(taipei?.name, "台北車站")
        // 台北車站 is two metro nodes; both resolve back to the same interchange.
        XCTAssertEqual(InterchangeRegistry.byTRTC("BL12")?.name, "台北車站")
        XCTAssertEqual(InterchangeRegistry.byTRTC("R10")?.name, "台北車站")
    }

    func testUnknownIDsResolveToNil() {
        XCTAssertNil(InterchangeRegistry.byTRA("9999"))
        XCTAssertNil(InterchangeRegistry.byTRTC("ZZ99"))
    }
}
