// Sources/Rush/Server.swift
import Foundation
import MCP

enum TransportServer {
    static func run() async {
        let server = Server(
            name: "rush",
            version: AppVersion.version,
            capabilities: .init(tools: .init())
        )

        let cache = Cache()
        let client = TDXClient()
        let registry = ToolRegistry()

        // Each transport mode module appends its tools + dispatcher into the
        // shared registry. The single ListTools / CallTool handlers below
        // delegate to the registry so adding a new mode doesn't require
        // changing wiring here.
        await RailTools.register(into: registry, client: client, cache: cache)
        await MetroTools.register(into: registry, client: client, cache: cache)
        await BusTools.register(into: registry, client: client, cache: cache)
        await BikeTools.register(into: registry, client: client, cache: cache)
        await AirTools.register(into: registry, client: client, cache: cache)
        await TrafficTools.register(into: registry, client: client, cache: cache)
        await ParkingTools.register(into: registry, client: client, cache: cache)
        await TransitTools.register(into: registry, client: client, cache: cache)

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: await registry.allTools())
        }
        await server.withMethodHandler(CallTool.self) { params in
            await registry.handleCall(name: params.name, arguments: params.arguments ?? [:])
        }

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
