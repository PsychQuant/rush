import XCTest
@testable import Rush

final class AuthTests: XCTestCase {
    let testService = "che-transport-tdx-test"

    override func tearDown() async throws {
        try? Auth.delete(service: testService)
    }

    func testWriteAndRead() throws {
        try Auth.save(service: testService, account: "client_id", value: "abc123")
        let got = try Auth.read(service: testService, account: "client_id")
        XCTAssertEqual(got, "abc123")
    }

    func testReadMissingThrows() {
        XCTAssertThrowsError(try Auth.read(service: testService, account: "nope"))
    }
}
