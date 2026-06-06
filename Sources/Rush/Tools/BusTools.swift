// Sources/Rush/Tools/BusTools.swift
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
            ),
            Tool(
                name: "bus_route",
                description: "市內公車直達路由（暫不含轉乘）：給 from_stop、to_stop（站名或 StopUID）與 city，回經過兩站（起站在迄站之前、同方向）的直達路線；每條附上車預估（A2 即時 source:live／班表發車 source:scheduled／班距期望 source:frequency）+ 抵達時刻（有班表才給 source:scheduled；frequency-only 路線抵達從缺 + note，不假裝精確）。站名多筆同名 → 回 matches 釐清。無直達 → routes:[] + note（轉乘尚未支援，Stage 3b）。僅單一城市內。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from_stop": .object(["type": .string("string"), "description": .string("起站站名或 StopUID")]),
                        "to_stop": .object(["type": .string("string"), "description": .string("迄站站名或 StopUID")]),
                        "city": .object(["type": .string("string"), "description": .string("城市代碼"), "enum": cityEnum]),
                        "depart_after": .object(["type": .string("string"), "description": .string("出發時間 HH:mm（Asia/Taipei），預設現在")])
                    ]),
                    "required": .array([.string("from_stop"), .string("to_stop"), .string("city")]),
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
            case "bus_route":
                return try await executeBusRoute(arguments: arguments, client: client, cache: cache)
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

    /// bus_route — direct-route within-city bus routing (Stage 3a). Resolves the two
    /// stops, intersects StopOfRoute for routes serving origin→dest in one direction,
    /// then composes board (A2 live / schedule / headway) + arrival (timetable or omit)
    /// via `BusRouter`. Transfers deferred to 3b.
    private static func executeBusRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let fromQ = arguments["from_stop"]?.stringValue, !fromQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from_stop")
        }
        guard let toQ = arguments["to_stop"]?.stringValue, !toQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to_stop")
        }
        let city = try parseCity(arguments)
        let nowMin = nowMinutesTaipei()
        let weekday = weekdayTaipei()
        let departAfterMin = arguments["depart_after"]?.stringValue.flatMap(TimetableRouter.minutesOfDay) ?? nowMin
        let departAfter = TimetableRouter.clock(departAfterMin)

        // Resolve both stops (name or StopUID). Ambiguous / not-found short-circuits.
        let stops = decodeList(BusStop.self, data: try await client.fetch(
            path: TDXEndpoints.busStop(city.rawValue), cacheTTL: 86400, cache: cache))
        let from: (uid: String, name: String)
        switch resolveStop(fromQ, role: "from_stop", stops: stops, city: city, departAfter: departAfter) {
        case .one(let u, let n): from = (u, n)
        case .result(let r): return r
        }
        let to: (uid: String, name: String)
        switch resolveStop(toQ, role: "to_stop", stops: stops, city: city, departAfter: departAfter) {
        case .one(let u, let n): to = (u, n)
        case .result(let r): return r
        }

        // Candidate direct routes: serve origin then dest in the same direction (ordered Stops).
        let routes = decodeList(BusStopOfRoute.self, data: try await client.fetch(
            path: TDXEndpoints.busStopOfRoute(city.rawValue), cacheTTL: 3600, cache: cache))
        var candidates: [BusRouter.Candidate] = []
        for r in routes {
            guard let oi = r.stops.firstIndex(where: { $0.stopUID == from.uid }),
                  let di = r.stops.firstIndex(where: { $0.stopUID == to.uid }), oi < di else { continue }
            candidates.append(.init(
                routeUID: r.routeUID, routeName: r.routeName.zhTw ?? r.routeUID, subRouteName: nil,
                direction: r.direction ?? 0,
                originStopUID: from.uid, originStopName: r.stops[oi].stopName.zhTw ?? from.name,
                destStopUID: to.uid, destStopName: r.stops[di].stopName.zhTw ?? to.name))
        }
        if candidates.isEmpty {
            return ToolResult.json([
                "from": from.name, "to": to.name, "city": city.rawValue, "depart_after": departAfter,
                "routes": [[String: Any]](),
                "note": "查無直達 \(from.name) → \(to.name) 的公車路線；轉乘路由尚未支援（Stage 3b）"])
        }

        // A2 live ETA at the origin stop (graceful — fall back to schedule/headway).
        var a2BySig: [String: Int] = [:]
        if let a2 = try? await client.fetch(
            path: TDXEndpoints.busEstimatedTimeOfArrival(city.rawValue),
            queryItems: [URLQueryItem(name: "$filter", value: "StopUID eq '\(from.uid)'")],
            cacheTTL: 0, cache: cache) {
            for a in decodeList(BusArrival.self, data: a2) {
                guard let ru = a.routeUID, let eta = a.estimateTime, eta >= 0, (a.stopStatus ?? 0) == 0 else { continue }
                a2BySig[BusRouter.sig(ru, a.direction ?? 0)] = eta
            }
        }
        // Schedule (graceful — without it, arrival is omitted + board falls to A2 only).
        var scheduleBySig: [String: BusSchedule] = [:]
        if let sc = try? await client.fetch(path: TDXEndpoints.busSchedule(city.rawValue), cacheTTL: 3600, cache: cache) {
            for s in decodeList(BusSchedule.self, data: sc) {
                let k = BusRouter.sig(s.routeUID, s.direction ?? 0)
                if scheduleBySig[k] == nil { scheduleBySig[k] = s }
            }
        }

        // Stage 3c-ii.3: dispatch through RaptorCore's bus-direct facade (delegates to
        // BusRouter; structural routing-through-the-core, not ensemble capability).
        let options = RaptorCore.planBusDirect(candidates: candidates, a2BySig: a2BySig, scheduleBySig: scheduleBySig,
                                               nowMin: nowMin, departAfterMin: departAfterMin, weekday: weekday)
        let routesOut: [[String: Any]] = options.map { o in
            var d: [String: Any] = [
                "route_name": o.routeName, "direction": o.direction,
                "board_stop": o.boardStop, "alight_stop": o.alightStop, "board_source": o.boardSource]
            if let sub = o.subRouteName { d["sub_route_name"] = sub }
            if let b = o.boardInMin { d["board_in_min"] = b }
            if let at = o.arrivalTime {
                d["arrival_time"] = at; d["arrival_source"] = o.arrivalSource ?? "scheduled"
            } else {
                d["arrival_time"] = NSNull()
            }
            if let n = o.note { d["note"] = n }
            return d
        }
        return ToolResult.json([
            "from": from.name, "to": to.name, "city": city.rawValue, "depart_after": departAfter,
            "routes": routesOut])
    }

    /// Stop resolution: exact StopUID, else fuzzy by name. One physical stop → `.one`;
    /// none or multiple → a ready `CallTool.Result` (note / matches) to return directly.
    private enum StopResolution { case one(uid: String, name: String); case result(CallTool.Result) }

    private static func resolveStop(_ q: String, role: String, stops: [BusStop],
                                    city: BusCity, departAfter: String) -> StopResolution {
        if let s = stops.first(where: { $0.stopUID == q }) {
            return .one(uid: s.stopUID, name: s.stopName.zhTw ?? s.stopUID)
        }
        let matched = fuzzyMatchStops(query: q, in: stops)
        if matched.isEmpty {
            return .result(ToolResult.json([
                "query": q, "role": role, "city": city.rawValue, "depart_after": departAfter,
                "routes": [[String: Any]](), "note": "查無 \(role) 站「\(q)」"]))
        }
        let uniqueUIDs = Set(matched.map { $0.stopUID })
        if uniqueUIDs.count == 1, let s = matched.first {
            return .one(uid: s.stopUID, name: s.stopName.zhTw ?? s.stopUID)
        }
        let ms = matched.prefix(20).map { s -> [String: Any] in
            var d: [String: Any] = ["stop_uid": s.stopUID, "name": s.stopName.zhTw ?? ""]
            if let p = s.stopPosition { d["lat"] = p.positionLat; d["lon"] = p.positionLon }
            return d
        }
        return .result(ToolResult.json([
            "ambiguous": role, "query": q, "city": city.rawValue, "matches": Array(ms),
            "note": "「\(q)」對應多個站牌，請改用 StopUID 或更精確站名"]))
    }

    private static func nowMinutesTaipei() -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let n = Date(); return cal.component(.hour, from: n) * 60 + cal.component(.minute, from: n)
    }
    private static func weekdayTaipei() -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.component(.weekday, from: Date())
    }

    private static func executeSearchRoutes(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let (query, city) = try parseQueryCity(arguments)
        let data = try await client.fetch(
            path: TDXEndpoints.busRoute(city.rawValue),
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
        return ToolResult.json(["matches": matches, "city": city.rawValue])
    }

    private static func executeSearchStops(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let (query, city) = try parseQueryCity(arguments)
        let data = try await client.fetch(
            path: TDXEndpoints.busStop(city.rawValue),
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
        return ToolResult.json(["matches": matches, "city": city.rawValue])
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
            path: TDXEndpoints.busStopOfRoute(city.rawValue),
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
        return ToolResult.json(["matches": matches, "city": city.rawValue, "from_stop": fromStop, "to_stop": toStop])
    }

    private static func executeStatusArrivals(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let stopID = arguments["stop_id"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: stop_id")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: TDXEndpoints.busEstimatedTimeOfArrival(city.rawValue),
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
        return ToolResult.json(["arrivals": payload, "city": city.rawValue, "stop_id": stopID])
    }

    private static func executeStatusPositions(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let routeName = arguments["route_name"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: route_name")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: TDXEndpoints.busRealTimeNearStop(city.rawValue, route: routeName),
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
        return ToolResult.json(["positions": payload, "city": city.rawValue, "route_name": routeName])
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
}
