import XCTest
@testable import Rush

final class AirToolsTests: XCTestCase {
    func testDefineToolsReturnsThree() {
        let names = AirTools.defineTools().map(\.name)
        XCTAssertEqual(Set(names), Set([
            "air_list_airports",
            "air_find_flights",
            "air_status_flights"
        ]))
    }

    func testParseAirportNormalizesToUppercase() throws {
        let (airport, dir) = try AirTools.parseAirportDirection([
            "airport": .string("tpe"),
            "direction": .string("Arrival")
        ])
        XCTAssertEqual(airport, "TPE", "IATA codes are upper-case by convention; tool normalizes input")
        XCTAssertEqual(dir, "Arrival")
    }

    func testParseAirportRejectsNonIATA() {
        for bad in ["TP", "TPEX", "12A", ""] {
            do {
                _ = try AirTools.parseAirportDirection([
                    "airport": .string(bad),
                    "direction": .string("Arrival")
                ])
                XCTFail("'\(bad)' should not pass IATA validation")
            } catch let TDXError.decoding(msg) {
                XCTAssertTrue(msg.contains("IATA"))
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testParseDirectionRejectsInvalid() {
        do {
            _ = try AirTools.parseAirportDirection([
                "airport": .string("TPE"),
                "direction": .string("Sideways")
            ])
            XCTFail("invalid direction should throw")
        } catch let TDXError.decoding(msg) {
            XCTAssertTrue(msg.contains("direction must be"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
