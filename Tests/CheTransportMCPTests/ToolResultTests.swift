// Tests/CheTransportMCPTests/ToolResultTests.swift
import XCTest
import MCP
@testable import CheTransportMCP

/// Direct coverage for the shared `ToolResult.json(_:)` serialization helper (#3).
///
/// The seven per-module helpers it replaces (`jsonResult` × 5,
/// `MetroTools.resultJSON`, `RailTools.routeResult`) never had their own test —
/// they were only exercised transitively through executor tests. These pin the
/// two guarantees the shared helper must keep: a `CallTool.Result` carrying the
/// serialized text, and `JSONSanitize.clean` applied on the way out.
final class ToolResultTests: XCTestCase {

    /// A plain dict serializes to its exact compact JSON, wrapped in a text result.
    func testSerializesPlainDict() {
        let text = TestSupport.textContent(ToolResult.json(["a": 1]))
        XCTAssertEqual(text, #"{"a":1}"#)
    }

    /// The sanitize step is applied: 25.04 (no exact IEEE-754 form) must emit the
    /// clean decimal, not 25.039999999999999. This is the whole reason the helper
    /// centralizes the `JSONSanitize.clean` call (#1).
    func testAppliesJSONSanitize() {
        let text = TestSupport.textContent(ToolResult.json(["lat": 25.04]))
        XCTAssertEqual(text, #"{"lat":25.04}"#)
    }
}
