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

    /// Returns the path to a working `che-keychain` binary if one is installed in
    /// a known location, or nil to fall back to the in-binary getpass flow.
    static func findCheKeychain() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/che-keychain"),
            URL(fileURLWithPath: "/usr/local/bin/che-keychain"),
            URL(fileURLWithPath: "/opt/homebrew/bin/che-keychain")
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        // Fall back to PATH lookup via `env`. We avoid hard-coding more dirs.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "che-keychain"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    /// Invokes che-keychain set-pair to collect creds via a native macOS
    /// dialog. Returns the exit code from che-keychain (0 = stored, 2 =
    /// cancelled, other = error).
    static func runViaCheKeychain(at url: URL) -> Int32 {
        let p = Process()
        p.executableURL = url
        p.arguments = [
            "set-pair",
            "--service", Auth.defaultService,
            "--visible-account", "client_id",
            "--secure-account", "client_secret",
            "--visible-label", "TDX client_id",
            "--secure-label", "TDX client_secret",
            "--title", "che-transport-mcp — TDX setup",
            "--explain", "Free TDX account: https://tdx.transportdata.tw/register  •  會員中心 → 資料服務 → API 金鑰 → 編輯"
        ]
        // Don't pipe stdio — let che-keychain own its terminal output if any
        // (and present its native dialog to the user, which is the whole point).
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            FileHandle.standardError.write(Data("✗ failed to launch che-keychain: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// Runs the interactive setup flow. Prefers a native dialog via che-keychain
    /// if installed; falls back to in-process getpass otherwise.
    /// Returns a process exit code.
    static func run() async -> Int32 {
        if let cheKeychain = findCheKeychain() {
            print("→ Delegating credential prompt to che-keychain at \(cheKeychain.path)")
            print("  (A native dialog will appear — type your credentials there, not here.)")
            let code = runViaCheKeychain(at: cheKeychain)
            switch code {
            case 0:
                // che-keychain wrote both accounts to the keychain. Fall through
                // to OAuth verification below.
                print("✓ Credentials stored via che-keychain (service: \(Auth.defaultService))")
            case 2:
                FileHandle.standardError.write(Data("Cancelled.\n".utf8))
                return 2
            default:
                FileHandle.standardError.write(Data("✗ che-keychain returned exit code \(code).\n".utf8))
                return code
            }
        } else {
            print("""
            che-transport-mcp — TDX credential setup
            ────────────────────────────────────────
            Register a free TDX account first: https://tdx.transportdata.tw/register
            會員中心 → 資料服務 → API 金鑰 → 編輯 → copy client_id + client_secret

            (Tip: install `che-keychain` (https://github.com/PsychQuant/che-keychain)
            for a native dialog instead of this terminal prompt.)

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
        }

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
