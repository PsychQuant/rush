import XCTest
@testable import CheTransportMCP

/// Offline tests for the bare-vs-wrapped list decoder. TDX serves list data in
/// two shapes; `TDXDecode.list` must transparently handle both.
final class TDXDecodeTests: XCTestCase {
    private struct Row: Codable, Equatable { let id: String }

    func testDecodesBareArray() {
        let data = Data(#"[{"id":"a"},{"id":"b"}]"#.utf8)
        XCTAssertEqual(TDXDecode.list(Row.self, from: data), [Row(id: "a"), Row(id: "b")])
    }

    func testDecodesWrappedObjectArray() {
        // PTX-style wrapper: scalar metadata + one data array under a dataset key.
        let data = Data(#"{"UpdateTime":"t","AuthorityCode":"X","Rows":[{"id":"a"}]}"#.utf8)
        XCTAssertEqual(TDXDecode.list(Row.self, from: data), [Row(id: "a")])
    }

    func testReturnsEmptyOnUndecodableBody() {
        // Production stays lenient (empty ≠ error); contract tests assert strictly.
        XCTAssertEqual(TDXDecode.list(Row.self, from: Data(#"{"message":"Resource Not Found"}"#.utf8)), [])
        XCTAssertEqual(TDXDecode.list(Row.self, from: Data("not json".utf8)), [])
    }
}
