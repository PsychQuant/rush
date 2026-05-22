import XCTest
@testable import CheTransportMCP

final class SetupTests: XCTestCase {
    func testValidateAcceptsRealCredentials() {
        XCTAssertNoThrow(try Setup.validate(clientID: "abc-client-id", clientSecret: "s3cr3t-value"))
    }

    func testValidateTrimsSurroundingWhitespace() {
        // A user pasting from the TDX portal often picks up trailing spaces/newlines.
        XCTAssertNoThrow(try Setup.validate(clientID: "  abc  ", clientSecret: "\tsecret\n"))
    }

    func testValidateRejectsEmptyClientID() {
        XCTAssertThrowsError(try Setup.validate(clientID: "", clientSecret: "secret")) { error in
            guard case SetupError.emptyField(let field) = error else {
                return XCTFail("expected SetupError.emptyField, got \(error)")
            }
            XCTAssertEqual(field, "client_id")
        }
    }

    func testValidateRejectsWhitespaceOnlyClientID() {
        XCTAssertThrowsError(try Setup.validate(clientID: "   ", clientSecret: "secret")) { error in
            guard case SetupError.emptyField(let field) = error else {
                return XCTFail("expected SetupError.emptyField, got \(error)")
            }
            XCTAssertEqual(field, "client_id", "whitespace-only input trims to empty")
        }
    }

    func testValidateRejectsEmptyClientSecret() {
        XCTAssertThrowsError(try Setup.validate(clientID: "abc", clientSecret: "")) { error in
            guard case SetupError.emptyField(let field) = error else {
                return XCTFail("expected SetupError.emptyField, got \(error)")
            }
            XCTAssertEqual(field, "client_secret")
        }
    }

    func testSetupErrorMessagesAreActionable() {
        XCTAssertEqual(SetupError.emptyField("client_id").errorDescription, "client_id must not be empty")
        XCTAssertEqual(SetupError.noInput("client_secret").errorDescription, "no input received for client_secret")
    }
}
