import XCTest
@testable import CheTransportMCP

/// Unit tests for `JSONSanitize.clean(_:)` — the shortest-round-trippable Double
/// sanitizer that removes IEEE-754 formatting noise from tool JSON output (#1).
///
/// These pin the guarantees documented on `JSONSanitize`: clean rendering,
/// value-preservation (exact round-trip), Int/Bool type-safety, recursion through
/// nested structures, and non-finite pass-through.
final class JSONSanitizeTests: XCTestCase {

    /// Serialize through the sanitizer the same way the executors do.
    private func sanitizedJSON(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: JSONSanitize.clean(obj),
                                              options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func testCleansFloatNoise() throws {
        // 25.04 has no exact IEEE-754 representation → raw JSONSerialization emits
        // 25.039999999999999. The sanitizer must produce the clean form.
        XCTAssertEqual(try sanitizedJSON(["lat": 25.04]), #"{"lat":25.04}"#)
    }

    func testPreservesAlreadyCleanDouble() throws {
        XCTAssertEqual(try sanitizedJSON(["lon": 121.56]), #"{"lon":121.56}"#)
    }

    func testNegativeCoordinate() throws {
        XCTAssertEqual(try sanitizedJSON(["lon": -121.5654]), #"{"lon":-121.5654}"#)
    }

    func testHighPrecisionCoordinatePreserved() throws {
        XCTAssertEqual(try sanitizedJSON(["lat": 25.0478]), #"{"lat":25.0478}"#)
    }

    func testIntegerValuedDoubleRendersAsIntegerButRoundTrips() throws {
        // The one observable change: 25.0 renders as 25 (identical JSON number).
        XCTAssertEqual(try sanitizedJSON(["lat": 25.0]), #"{"lat":25}"#)

        let data = try JSONSerialization.data(withJSONObject: JSONSanitize.clean(["lat": 25.0]))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((parsed["lat"] as? NSNumber)?.doubleValue, 25.0, "round-trips back to 25.0")
    }

    func testRoundTripIsNumericallyExact() throws {
        // Includes the adversarial magnitudes the design claims to handle:
        // ordinary coords/fares, scientific-notation small/large, the NSDecimal
        // out-of-range extremes (which take the raw-Double fallback path), and
        // -0.0 (round-trips to 0.0, since -0.0 == 0.0).
        let values: [Double] = [
            25.04, -121.5654, 0.1, 13.456789, 88.5,
            1e-7, 1e20, 1e-300, 1e300, -0.0, 0.1 + 0.2,
            Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude
        ]
        for value in values {
            let data = try JSONSerialization.data(withJSONObject: JSONSanitize.clean(["v": value]))
            let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual((parsed["v"] as? NSNumber)?.doubleValue, value,
                           "sanitized \(value) must parse back numerically equal")
        }
    }

    func testRecursesIntoNestedArraysAndDicts() throws {
        // Mirror a bus_status_positions payload: array of dicts holding coordinates.
        let payload: [String: Any] = [
            "positions": [
                ["lat": 25.04, "lon": 121.56],
                ["lat": 24.99999999, "lon": -120.5]
            ]
        ]
        let json = try sanitizedJSON(payload)
        XCTAssertTrue(json.contains(#""lat":25.04"#), "nested lat cleaned; got \(json)")
        XCTAssertTrue(json.contains(#""lon":121.56"#), "nested lon cleaned; got \(json)")
        XCTAssertTrue(json.contains(#""lat":24.99999999"#), "deep coord cleaned; got \(json)")
        XCTAssertFalse(json.contains("999999999999"), "no IEEE-754 noise anywhere; got \(json)")
    }

    func testPreservesIntAndBool() throws {
        // Int must not become a decimal; Bool must stay true, NOT 1.
        let json = try sanitizedJSON(["count": 3, "live": true, "lat": 25.04])
        XCTAssertTrue(json.contains(#""count":3"#), "Int preserved; got \(json)")
        XCTAssertTrue(json.contains(#""live":true"#), "Bool preserved (not 1); got \(json)")
        XCTAssertTrue(json.contains(#""lat":25.04"#), "Double cleaned alongside; got \(json)")
    }

    func testStringsAndNullPassThrough() throws {
        let json = try sanitizedJSON(["name": "中山", "note": NSNull()])
        XCTAssertTrue(json.contains(#""name":"中山""#))
        XCTAssertTrue(json.contains(#""note":null"#))
    }

    func testNonFiniteDoublePassesThroughUnchanged() {
        // inf/nan are returned as-is so JSONSerialization rejects them exactly as
        // it does for a raw Double — no behaviour change, no silent corruption.
        let cleaned = JSONSanitize.clean(["v": Double.infinity])
        XCTAssertFalse(JSONSerialization.isValidJSONObject(cleaned),
                       "non-finite still rejected by JSONSerialization, as before")
    }
}
