// Sources/Rush/main.swift
import Foundation
import MCP

if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print(AppVersion.versionString)
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print(AppVersion.helpMessage)
    exit(0)
}

if CommandLine.arguments.contains("--setup") {
    let code = await Setup.run()
    exit(code)
}

if CommandLine.arguments.contains("--check-auth") {
    do {
        _ = try Auth.read(account: "client_id")
        _ = try Auth.read(account: "client_secret")
        let client = TDXClient()
        _ = try await client.ensureToken()
        print("✓ TDX credentials valid")
        exit(0)
    } catch {
        let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        FileHandle.standardError.write(Data("✗ \(msg)\n".utf8))
        exit(1)
    }
}

await TransportServer.run()
