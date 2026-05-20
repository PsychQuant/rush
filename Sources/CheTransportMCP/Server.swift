// Sources/CheTransportMCP/Server.swift
import Foundation
import MCP

enum TransportServer {
    static func run() async {
        let server = Server(
            name: "che-transport-mcp",
            version: AppVersion.version,
            capabilities: .init(tools: .init())
        )

        let cache = Cache()
        let client = TDXClient()

        // Register Rail tools (Tasks 10-14 will populate)
        await RailTools.register(server: server, client: client, cache: cache)

        let transport = StdioTransport()
        do {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("Server error: \(msg)\n".utf8))
            exit(1)
        }
    }
}
