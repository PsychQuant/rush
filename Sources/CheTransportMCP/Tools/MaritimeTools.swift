// Sources/CheTransportMCP/Tools/MaritimeTools.swift
import Foundation
import MCP

enum MaritimeTools {
    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "maritime_list_routes",
                description: "列出 TDX 收錄的台灣客運船舶（渡輪／海運）所有航線。可選 operator_id 收斂到單一營運業者。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "operator_id": .object([
                            "type": .string("string"),
                            "description": .string("（可選）營運業者代碼，例如 TWNC 台馬輪")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "maritime_status_schedule",
                description: "查特定航線的時刻表與即時狀態。Raw TDX JSON 直接回傳（航班 schema 因業者而異）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "route_id": .object([
                            "type": .string("string"),
                            "description": .string("航線代碼（用 maritime_list_routes 取得）")
                        ])
                    ]),
                    "required": .array([.string("route_id")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            )
        ]
    }

    static func register(into registry: ToolRegistry, client: TDXClient, cache: Cache) async {
        await registry.register(tools: defineTools()) { name, args in
            await handleCall(name: name, arguments: args, client: client, cache: cache)
        }
    }

    static func handleCall(name: String, arguments: [String: Value], client: TDXClient, cache: Cache) async -> CallTool.Result {
        do {
            switch name {
            case "maritime_list_routes":
                return try await executeListRoutes(arguments: arguments, client: client, cache: cache)
            case "maritime_status_schedule":
                return try await executeStatusSchedule(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown maritime tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func executeListRoutes(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        var queryItems: [URLQueryItem] = []
        if let opID = arguments["operator_id"]?.stringValue, !opID.isEmpty {
            queryItems.append(URLQueryItem(name: "$filter", value: "OperatorID eq '\(opID)'"))
        }
        let data = try await client.fetch(
            path: "v2/Maritime/Route",
            queryItems: queryItems,
            cacheTTL: 86400,
            cache: cache
        )
        let routes = (try? JSONDecoder().decode([MaritimeRoute].self, from: data)) ?? []
        let payload = routes.map { route -> [String: Any] in
            [
                "route_id": route.routeID,
                "name_zh": route.routeName?.zhTw ?? "",
                "name_en": route.routeName?.en ?? "",
                "operator": route.operatorID ?? "",
                "from_stop": route.departureStopID ?? "",
                "to_stop": route.destinationStopID ?? "",
                "from_name": route.departureStopName?.zhTw ?? "",
                "to_name": route.destinationStopName?.zhTw ?? ""
            ]
        }
        return jsonResult(["routes": payload])
    }

    private static func executeStatusSchedule(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let routeID = arguments["route_id"]?.stringValue, !routeID.isEmpty else {
            throw TDXError.decoding("Missing required parameter: route_id")
        }
        let data = try await client.fetch(
            path: "v2/Maritime/Schedule",
            queryItems: [URLQueryItem(name: "$filter", value: "RouteID eq '\(routeID)'")],
            cacheTTL: 3600,
            cache: cache
        )
        let text = String(data: data, encoding: .utf8) ?? "[]"
        // Wrap raw TDX response so LLM sees the route context alongside the raw payload.
        let envelope = "{\"route_id\":\"\(routeID)\",\"raw\":\(text)}"
        return CallTool.Result(content: [.text(text: envelope, annotations: nil, _meta: nil)])
    }

    static func jsonResult(_ obj: [String: Any]) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: JSONSanitize.clean(obj))) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}
