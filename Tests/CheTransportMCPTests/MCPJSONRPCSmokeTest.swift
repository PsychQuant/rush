import XCTest
@testable import CheTransportMCP

/// End-to-end MCP JSON-RPC smoke test.
///
/// Spawns the built `CheTransportMCP` binary as a child process, drives it
/// via stdio with three JSON-RPC messages (initialize → initialized →
/// tools/list), then verifies:
///   1. The server identifies itself as "che-transport-mcp" with the
///      expected version.
///   2. tools/list returns **exactly 23** tools.
///   3. Per-prefix counts match the design spec
///      (rail=6, metro=1, bus=5, bike=3, air=3, traffic=3, parking=2).
///   4. Every tool entry has a non-empty `name`, `description`, and
///      `inputSchema` field.
///
/// What unit tests already cover: each `defineTools()` function returns
/// the right shape. What this test adds: the whole binary actually starts,
/// installs the `ListTools` / `CallTool` handlers, and serves them via
/// MCP's stdio transport. The cheapest "the whole stack still works" check
/// we have.
///
/// Notes:
/// - The test is skipped (not failed) when the executable can't be found,
///   so `swift test` still completes cleanly on a fresh checkout where
///   the executable hasn't been built yet.
/// - No TDX credentials are required: `tools/list` is purely a metadata
///   call against the registry; nothing reaches the network.
final class MCPJSONRPCSmokeTest: XCTestCase {

    func testEndToEndInitializeAndToolsList() throws {
        guard let binaryURL = Self.findBuiltBinary() else {
            throw XCTSkip("""
                CheTransportMCP binary not found in .build/. Run `swift build` \
                first (or rely on `swift test` building the executable target).
                """)
        }

        // Spawn the server as a child process with pipes for stdin/stdout/stderr.
        let process = Process()
        process.executableURL = binaryURL
        let stdinPipe  = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput  = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        // We must register the termination handler BEFORE run() — the
        // process can in principle exit between run() and the assignment.
        let processExitedExpectation = expectation(description: "MCP server exits after stdin close")
        process.terminationHandler = { _ in processExitedExpectation.fulfill() }

        try process.run()

        // Three messages, one per line. The server returns a response for
        // requests (id=1, id=2) but not for notifications (initialized has
        // no id).
        let messages = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
        ]
        for message in messages {
            stdinPipe.fileHandleForWriting.write(Data((message + "\n").utf8))
        }

        // CRITICAL: don't close stdin until we have actually received the
        // tools/list response. The MCP swift-sdk's stdio transport unwinds
        // out of waitUntilCompleted() on EOF; if we close stdin while a
        // dispatch is still in flight, the response is dropped and the
        // server exits cleanly (terminationStatus 0) with empty stdout.
        // Polling for the id=2 response is more robust than a fixed sleep
        // because it adapts to real dispatch time.
        let outputText = Self.collectStdoutUntilLastResponseSeen(
            stdoutPipe.fileHandleForReading,
            expectedResponseIDs: [1, 2],
            timeout: 10.0
        )

        try stdinPipe.fileHandleForWriting.close()
        wait(for: [processExitedExpectation], timeout: 5.0)

        let stderrText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0,
                       "MCP server exited with non-zero status \(process.terminationStatus). stderr:\n\(stderrText)")

        // Parse the responses. The server emits one JSON-RPC object per line.
        let lines = outputText.split(whereSeparator: \.isNewline).map(String.init)

        var initResult: [String: Any]?
        var toolsResult: [String: Any]?
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = envelope["id"] as? Int
            else { continue }
            if id == 1 { initResult  = envelope["result"] as? [String: Any] }
            if id == 2 { toolsResult = envelope["result"] as? [String: Any] }
        }

        // 1. initialize → serverInfo identifies the binary
        guard let initResult = initResult else {
            return XCTFail("no response for initialize (id=1). Raw stdout:\n\(outputText)")
        }
        let serverInfo = initResult["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "che-transport-mcp",
                       "serverInfo.name should match the binary identity")
        XCTAssertNotNil(serverInfo?["version"] as? String,
                        "serverInfo.version should be present")

        // 2. tools/list → tools field present and 21 entries
        guard let toolsResult = toolsResult else {
            return XCTFail("no response for tools/list (id=2). Raw stdout:\n\(outputText)")
        }
        guard let tools = toolsResult["tools"] as? [[String: Any]] else {
            return XCTFail("tools/list result missing `tools` array. Result was: \(toolsResult)")
        }
        XCTAssertEqual(tools.count, 23,
                       "expected 23 tools, got \(tools.count). Names: \(tools.compactMap { $0["name"] as? String })")

        // 3. Per-prefix counts match the design spec
        let names = tools.compactMap { $0["name"] as? String }
        let expectedPrefixCounts: [(String, Int)] = [
            ("rail_",     6),
            ("metro_",    1),
            ("bus_",      5),
            ("bike_",     3),
            ("air_",      3),
            ("traffic_",  3),
            ("parking_",  2)
        ]
        for (prefix, expected) in expectedPrefixCounts {
            let actual = names.filter { $0.hasPrefix(prefix) }.count
            XCTAssertEqual(actual, expected,
                           "expected \(expected) tools with prefix `\(prefix)`, got \(actual)")
        }

        // 4. Every tool has the required schema fields
        for tool in tools {
            let name = (tool["name"] as? String) ?? "(unnamed)"
            XCTAssertNotNil(tool["description"] as? String, "tool \(name) missing description")
            XCTAssertNotNil(tool["inputSchema"], "tool \(name) missing inputSchema")
        }
    }

    // MARK: - helpers

    /// Drains stdout (via `availableData` polling) until JSON-RPC response
    /// envelopes for every id in `expectedResponseIDs` have been seen, or
    /// the timeout elapses. Returns the full text collected up to that point
    /// (caller still parses it into JSON-RPC envelopes).
    ///
    /// Why polling and not `readabilityHandler`: the handler fires on a
    /// background thread, which adds a synchronisation hop for what is a
    /// short-lived test. Polling with `availableData` keeps the assertion
    /// flow strictly synchronous on the test thread.
    private static func collectStdoutUntilLastResponseSeen(
        _ handle: FileHandle,
        expectedResponseIDs: Set<Int>,
        timeout: TimeInterval
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var collected = Data()
        var seenIDs: Set<Int> = []

        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            collected.append(chunk)

            // Lightweight detection: look for "id":N substrings rather than
            // re-parsing every chunk. If a chunk arrives split mid-line we
            // simply wait for the next chunk to complete it.
            if let text = String(data: collected, encoding: .utf8) {
                for id in expectedResponseIDs where text.contains("\"id\":\(id)") {
                    seenIDs.insert(id)
                }
                if seenIDs == expectedResponseIDs { break }
            }
        }
        return String(data: collected, encoding: .utf8) ?? ""
    }

    /// Locate the built binary across common SwiftPM build layouts. Returns
    /// nil if none of the candidates exist — caller should `XCTSkip` rather
    /// than `XCTFail` so a fresh-checkout test run doesn't surface a confusing
    /// "file not found" error.
    private static func findBuiltBinary() -> URL? {
        let candidates = [
            ".build/debug/CheTransportMCP",
            ".build/release/CheTransportMCP",
            ".build/apple/Products/Debug/CheTransportMCP",
            ".build/apple/Products/Release/CheTransportMCP"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
