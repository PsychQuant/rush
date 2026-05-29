// Sources/CheTransportMCP/Tools/BusTools.swift
import Foundation
import MCP

enum BusTools {
    // MARK: - Tool definitions

    static func defineTools() -> [Tool] {
        let cityEnum: Value = .array(BusCity.allCases.map { .string($0.rawValue) })
        return [
            Tool(
                name: "bus_search_routes",
                description: "依名稱／路線編號模糊搜尋市區公車路線。city 為必填。同名路線於不同城市需分別查詢。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("搜尋關鍵字（中或英文，支援臺/台互換）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼（用 BusCity 列舉，如 Taipei / Kaohsiung）"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("query"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bus_search_stops",
                description: "依名稱模糊搜尋公車站牌。city 必填。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("站名關鍵字（支援臺/台互換）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("query"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bus_find_routes",
                description: "找同時經過 from_stop 與 to_stop 兩個站牌的公車路線（O/D 候選）。city 必填。注意 from_stop 與 to_stop 是 StopUID。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from_stop": .object([
                            "type": .string("string"),
                            "description": .string("起站 StopUID（用 bus_search_stops 取得）")
                        ]),
                        "to_stop": .object([
                            "type": .string("string"),
                            "description": .string("迄站 StopUID")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("from_stop"), .string("to_stop"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bus_status_arrivals",
                description: "查某站牌即將到站的所有公車預估到達時間。回傳結果為 TDX 即時資料、不快取。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "stop_id": .object([
                            "type": .string("string"),
                            "description": .string("站牌 StopUID（用 bus_search_stops 取得）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("stop_id"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bus_status_positions",
                description: "查特定公車路線目前在哪些站點附近（即時位置）。輸入路線中文名（不是 RouteUID）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "route_name": .object([
                            "type": .string("string"),
                            "description": .string("路線中文名稱，如「307」或「1968」")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("route_name"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            )
        ]
    }

    // MARK: - Registry registration

    static func register(into registry: ToolRegistry, client: TDXClient, cache: Cache) async {
        await registry.register(tools: defineTools()) { name, args in
            await handleCall(name: name, arguments: args, client: client, cache: cache)
        }
    }

    // MARK: - Dispatch

    static func handleCall(name: String, arguments: [String: Value], client: TDXClient, cache: Cache) async -> CallTool.Result {
        do {
            switch name {
            case "bus_search_routes":
                return try await executeSearchRoutes(arguments: arguments, client: client, cache: cache)
            case "bus_search_stops":
                return try await executeSearchStops(arguments: arguments, client: client, cache: cache)
            case "bus_find_routes":
                return try await executeFindRoutes(arguments: arguments, client: client, cache: cache)
            case "bus_status_arrivals":
                return try await executeStatusArrivals(arguments: arguments, client: client, cache: cache)
            case "bus_status_positions":
                return try await executeStatusPositions(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown bus tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - Executors

    private static func executeSearchRoutes(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let (query, city) = try parseQueryCity(arguments)
        let data = try await client.fetch(
            path: "v2/Bus/Route/City/\(city.rawValue)",
            cacheTTL: 86400,
            cache: cache
        )
        let routes = decodeList(BusRoute.self, data: data)
        let matches = fuzzyMatchRoutes(query: query, in: routes).map { route -> [String: Any] in
            [
                "route_uid": route.routeUID,
                "route_id": route.routeID ?? "",
                "name_zh": route.routeName.zhTw ?? "",
                "name_en": route.routeName.en ?? "",
                "from": route.departureStopNameZh ?? "",
                "to": route.destinationStopNameZh ?? ""
            ]
        }
        return jsonResult(["matches": matches, "city": city.rawValue])
    }

    private static func executeSearchStops(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let (query, city) = try parseQueryCity(arguments)
        let data = try await client.fetch(
            path: "v2/Bus/Stop/City/\(city.rawValue)",
            cacheTTL: 86400,
            cache: cache
        )
        let stops = decodeList(BusStop.self, data: data)
        let matches = fuzzyMatchStops(query: query, in: stops).map { stop -> [String: Any] in
            var dict: [String: Any] = [
                "stop_uid": stop.stopUID,
                "stop_id": stop.stopID ?? "",
                "name_zh": stop.stopName.zhTw ?? "",
                "name_en": stop.stopName.en ?? ""
            ]
            if let pos = stop.stopPosition {
                dict["lat"] = pos.positionLat
                dict["lon"] = pos.positionLon
            }
            return dict
        }
        return jsonResult(["matches": matches, "city": city.rawValue])
    }

    private static func executeFindRoutes(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let fromStop = arguments["from_stop"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: from_stop")
        }
        guard let toStop = arguments["to_stop"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: to_stop")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: "v2/Bus/StopOfRoute/City/\(city.rawValue)",
            cacheTTL: 3600,
            cache: cache
        )
        let stopOfRoutes = decodeList(BusStopOfRoute.self, data: data)
        let matches = stopOfRoutes.compactMap { route -> [String: Any]? in
            let stopUIDs = Set(route.stops.map(\.stopUID))
            guard stopUIDs.contains(fromStop), stopUIDs.contains(toStop) else { return nil }
            return [
                "route_uid": route.routeUID,
                "name_zh": route.routeName.zhTw ?? "",
                "name_en": route.routeName.en ?? "",
                "direction": route.direction ?? -1
            ]
        }
        return jsonResult(["matches": matches, "city": city.rawValue, "from_stop": fromStop, "to_stop": toStop])
    }

    private static func executeStatusArrivals(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let stopID = arguments["stop_id"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: stop_id")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: "v2/Bus/EstimatedTimeOfArrival/City/\(city.rawValue)",
            queryItems: [URLQueryItem(name: "$filter", value: "StopUID eq '\(stopID)'")],
            cacheTTL: 0,
            cache: cache
        )
        let arrivals = decodeList(BusArrival.self, data: data)
        let payload = arrivals.map { a -> [String: Any] in
            [
                "route_uid": a.routeUID ?? "",
                "route_name": a.routeName?.zhTw ?? "",
                "direction": a.direction ?? -1,
                "eta_seconds": a.estimateTime ?? -1,
                "stop_status": a.stopStatus ?? 0
            ]
        }
        return jsonResult(["arrivals": payload, "city": city.rawValue, "stop_id": stopID])
    }

    private static func executeStatusPositions(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let routeName = arguments["route_name"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: route_name")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: "v2/Bus/RealTimeNearStop/City/\(city.rawValue)/\(routeName)",
            cacheTTL: 0,
            cache: cache
        )
        let positions = decodeList(BusLivePosition.self, data: data)
        let payload = positions.map { p -> [String: Any] in
            var dict: [String: Any] = [
                "plate": p.plateNumb ?? "",
                "route_uid": p.routeUID ?? "",
                "direction": p.direction ?? -1
            ]
            if let pos = p.busPosition {
                dict["lat"] = pos.positionLat
                dict["lon"] = pos.positionLon
            }
            return dict
        }
        return jsonResult(["positions": payload, "city": city.rawValue, "route_name": routeName])
    }

    // MARK: - Helpers

    static func parseQueryCity(_ arguments: [String: Value]) throws -> (String, BusCity) {
        guard let query = arguments["query"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: query")
        }
        return (query, try parseCity(arguments))
    }

    static func parseCity(_ arguments: [String: Value]) throws -> BusCity {
        guard let cityRaw = arguments["city"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: city")
        }
        guard let city = BusCity(rawValue: cityRaw) else {
            let valid = BusCity.allCases.map(\.rawValue).joined(separator: ", ")
            throw TDXError.decoding("Invalid city '\(cityRaw)'. Valid: \(valid)")
        }
        return city
    }

    static func fuzzyMatchRoutes(query: String, in routes: [BusRoute]) -> [BusRoute] {
        let normalized = normalize(query)
        return routes.filter { route in
            let zh = normalize(route.routeName.zhTw ?? "")
            let en = normalize(route.routeName.en ?? "")
            return zh.contains(normalized) || en.contains(normalized)
        }
    }

    static func fuzzyMatchStops(query: String, in stops: [BusStop]) -> [BusStop] {
        let normalized = normalize(query)
        return stops.filter { stop in
            let zh = normalize(stop.stopName.zhTw ?? "")
            let en = normalize(stop.stopName.en ?? "")
            return zh.contains(normalized) || en.contains(normalized)
        }
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "台", with: "臺").lowercased()
    }

    static func decodeList<T: Codable>(_ type: T.Type, data: Data) -> [T] {
        (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    static func jsonResult(_ obj: [String: Any]) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: JSONSanitize.clean(obj))) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}
