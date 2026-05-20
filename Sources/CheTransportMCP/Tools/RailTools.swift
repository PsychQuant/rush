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
            Tool(
                name: "rail_search_stations",
                description: "依名稱（中或英）模糊搜尋鐵路站點，回傳所有匹配站點與其所屬 system。「中山」會回傳多個 system 的同名站。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("搜尋關鍵字（中文或英文，支援臺/台互換）")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("限定特定 system（可選）"),
                            "enum": .array([
                                .string("TRA"), .string("THSR"), .string("TRTC"),
                                .string("TYMC"), .string("KRTC"), .string("TMRT"),
                                .string("NTDLRT"), .string("KLRT")
                            ])
                        ])
                    ]),
                    "required": .array([.string("query")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
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
            await handleCall(name: params.name, arguments: params.arguments ?? [:], client: client, cache: cache)
        }
    }

    // MARK: - Dispatch

    private static func handleCall(name: String, arguments: [String: Value], client: TDXClient, cache: Cache) async -> CallTool.Result {
        do {
            switch name {
            case "rail_list_systems":
                return try await executeListSystems()
            case "rail_search_stations":
                return try await executeSearchStations(arguments: arguments, client: client, cache: cache)
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

    private static func executeSearchStations(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let query = arguments["query"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: query")
        }
        let systemFilter: [RailSystem] = {
            if let s = arguments["system"]?.stringValue, let sys = RailSystem(rawValue: s) {
                return [sys]
            }
            return RailSystem.allCases
        }()

        var allMatches: [[String: Any]] = []
        for sys in systemFilter {
            let data = try await client.fetch(
                path: "\(sys.apiPath)/Station",
                cacheTTL: 86400,
                cache: cache
            )
            let stations = Self.decodeStationList(data: data)
            let matches = Self.fuzzyMatch(query: query, in: stations)
            for m in matches {
                allMatches.append([
                    "system": sys.rawValue,
                    "station_id": m.stationID,
                    "name_zh": m.stationName.zhTw ?? "",
                    "name_en": m.stationName.en ?? ""
                ])
            }
        }

        let json = try JSONSerialization.data(withJSONObject: ["matches": allMatches])
        let text = String(data: json, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}

// MARK: - Fuzzy match & decoding helpers

extension RailTools {
    static func fuzzyMatch(query: String, in stations: [RailStation]) -> [RailStation] {
        let normalizedQuery = query
            .replacingOccurrences(of: "台", with: "臺")
            .lowercased()
        return stations.filter { station in
            let zh = (station.stationName.zhTw ?? "").replacingOccurrences(of: "台", with: "臺").lowercased()
            let en = (station.stationName.en ?? "").lowercased()
            return zh.contains(normalizedQuery) || en.contains(normalizedQuery)
        }
    }

    static func decodeStationList(data: Data) -> [RailStation] {
        // Try wrapped form first (TRA v3): { "Stations": [...] }
        struct Wrapped: Codable { let Stations: [RailStation] }
        if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
            return wrapped.Stations
        }
        // Fall back to bare array (metro endpoints)
        return (try? JSONDecoder().decode([RailStation].self, from: data)) ?? []
    }
}
