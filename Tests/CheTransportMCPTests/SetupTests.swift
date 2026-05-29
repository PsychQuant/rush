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

    // MARK: - che-keychain discovery (Setup.findExecutable)

    /// Builds a unique temp directory and registers cleanup. Returns its URL.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("setup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Writes a file at `dir/name` and optionally marks it executable.
    @discardableResult
    private func writeFile(_ name: String, in dir: URL, executable: Bool) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } else {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        return url
    }

    func testFindExecutableReturnsMatchWhenPresent() throws {
        let dir = try makeTempDir()
        let binary = try writeFile("che-keychain", in: dir, executable: true)

        let found = Setup.findExecutable(named: "che-keychain", in: [dir])
        XCTAssertEqual(found?.path, binary.path)
    }

    func testFindExecutableReturnsNilWhenAbsent() throws {
        let dir = try makeTempDir()
        XCTAssertNil(Setup.findExecutable(named: "che-keychain", in: [dir]))
    }

    func testFindExecutableSkipsNonExecutableFile() throws {
        let dir = try makeTempDir()
        // File exists but lacks the executable bit — must not be treated as a hit.
        try writeFile("che-keychain", in: dir, executable: false)
        XCTAssertNil(Setup.findExecutable(named: "che-keychain", in: [dir]),
                     "a present-but-non-executable file should not count")
    }

    func testFindExecutableReturnsFirstDirectoryMatch() throws {
        let first = try makeTempDir()
        let second = try makeTempDir()
        let firstBinary = try writeFile("che-keychain", in: first, executable: true)
        try writeFile("che-keychain", in: second, executable: true)

        let found = Setup.findExecutable(named: "che-keychain", in: [first, second])
        XCTAssertEqual(found?.path, firstBinary.path, "earlier directory wins")
    }

    func testDefaultSearchDirectoriesIncludeUserBin() {
        let dirs = Setup.defaultSearchDirectories().map(\.path)
        let userBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin").path
        XCTAssertTrue(dirs.contains(userBin), "~/bin should be a search location")
        XCTAssertTrue(dirs.contains("/opt/homebrew/bin"), "Homebrew arm64 bin should be searched")
    }
}
