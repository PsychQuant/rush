// Sources/CheTransportMCP/Setup.swift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum SetupError: Error, LocalizedError {
    case emptyField(String)
    case noInput(String)

    var errorDescription: String? {
        switch self {
        case .emptyField(let field): return "\(field) must not be empty"
        case .noInput(let field): return "no input received for \(field)"
        }
    }
}

/// Interactive TDX credential setup, invoked via `CheTransportMCP --setup`.
///
/// Lives in the signed + notarized binary rather than a shell script so the
/// keychain write path shares code with `Auth.read` (no drift), the secret
/// prompt uses `getpass` (terminal echo disabled — more reliable than bash
/// `read -s` across shells), and the whole flow is unit-testable.
enum Setup {
    /// Validates trimmed credential inputs. Pure — unit-testable without I/O.
    static func validate(clientID: String, clientSecret: String) throws {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw SetupError.emptyField("client_id") }
        guard !secret.isEmpty else { throw SetupError.emptyField("client_secret") }
    }

    /// Reads a hidden line from the terminal (echo disabled). Returns nil if
    /// no controlling terminal is available.
    private static func readSecret(prompt: String) -> String? {
        guard let raw = getpass(prompt) else { return nil }
        return String(cString: raw)
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
        return 1
    }

    /// Runs the interactive setup flow. Returns a process exit code.
    static func run() async -> Int32 {
        print("""
        che-transport-mcp — TDX credential setup
        ────────────────────────────────────────
        Register a free TDX account first: https://tdx.transportdata.tw/register
        會員中心 → API 金鑰 → create a key → copy client_id + client_secret

        """)

        print("TDX client_id: ", terminator: "")
        guard let rawID = readLine(strippingNewline: true) else {
            return fail(SetupError.noInput("client_id").localizedDescription)
        }
        guard let rawSecret = readSecret(prompt: "TDX client_secret: ") else {
            return fail(SetupError.noInput("client_secret").localizedDescription)
        }

        let clientID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try validate(clientID: clientID, clientSecret: clientSecret)
        } catch {
            return fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        do {
            try Auth.save(account: "client_id", value: clientID)
            try Auth.save(account: "client_secret", value: clientSecret)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return fail("keychain write failed: \(msg)")
        }
        print("✓ Credentials stored in keychain (service: \(Auth.defaultService))")

        print("\nVerifying against TDX (real OAuth round-trip)...")
        do {
            _ = try await TDXClient().ensureToken()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("✗ verification failed: \(msg)\n".utf8))
            FileHandle.standardError.write(Data("  Credentials were stored but TDX rejected them. Re-run --setup.\n".utf8))
            return 1
        }

        print("""

        ✓ TDX credentials valid — setup complete.

        Last step: fully quit Claude Code (Cmd+Q) and reopen so the MCP server
        picks up the new credentials.
        """)
        return 0
    }
}
