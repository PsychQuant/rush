// Sources/CheTransportMCP/Tools/RailTools.swift
import Foundation
import MCP

enum RailTools {
    // MARK: - Pure business logic (testable without a server)

    /// Returns all 8 supported rail system codes with display names.
    static func listSystems() -> [[String: String]] {
        RailSystem.allCases.map { sys in
            ["code": sys.rawValue, "name": sys.displayName]
        }
    }

    // MARK: - Tool definitions

    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "rail_list_systems",
                description: "列出此 MCP 支援的所有鐵路 system 代碼（TRA, THSR, 各捷運與輕軌）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
        ]
    }

    // MARK: - Server registration

    static func register(server: Server, client: TDXClient, cache: Cache) async {
        let tools = defineTools()

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleCall(name: params.name, arguments: params.arguments ?? [:])
        }
    }

    // MARK: - Dispatch

    private static func handleCall(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            switch name {
            case "rail_list_systems":
                return try await executeListSystems()
            default:
                return CallTool.Result(content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - Tool handlers

    private static func executeListSystems() async throws -> CallTool.Result {
        let systems = listSystems()
        let data = try JSONSerialization.data(withJSONObject: ["systems": systems])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
    }
}
