// Sources/Rush/Tools/RailTools.swift
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
                name: "rail_find_trains",
                description: "依起站、迄站、日期查詢班次。回傳該日從 from 到 to 的所有班次（含車種與時刻）。僅支援 TRA 與 THSR。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object([
                            "type": .string("string"),
                            "description": .string("起站 ID（用 rail_search_stations 查詢）")
                        ]),
                        "to": .object([
                            "type": .string("string"),
                            "description": .string("迄站 ID（用 rail_search_stations 查詢）")
                        ]),
                        "date": .object([
                            "type": .string("string"),
                            "description": .string("查詢日期，格式 YYYY-MM-DD（Asia/Taipei 時區）")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("鐵路系統代碼，僅支援 TRA 或 THSR"),
                            "enum": .array([.string("TRA"), .string("THSR")])
                        ])
                    ]),
                    "required": .array([.string("from"), .string("to"), .string("date"), .string("system")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
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
            Tool(
                name: "rail_status_train",
                description: "查特定列車（TRA）的即時誤點與位置。TDX 未提供高鐵（THSR）即時車況，故僅支援 TRA。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "train_no": .object([
                            "type": .string("string"),
                            "description": .string("列車車號")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("鐵路系統代碼，僅支援 TRA"),
                            "enum": .array([.string("TRA")])
                        ])
                    ]),
                    "required": .array([.string("train_no"), .string("system")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "rail_status_station",
                description: "查特定站點（TRA）近期到站列車（含誤點）。預設視窗 60 分鐘。TDX 未提供高鐵（THSR）即時車況，故僅支援 TRA。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "station_id": .object([
                            "type": .string("string"),
                            "description": .string("站點 ID（用 rail_search_stations 查詢）")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("鐵路系統代碼，僅支援 TRA"),
                            "enum": .array([.string("TRA")])
                        ]),
                        "window_min": .object([
                            "type": .string("integer"),
                            "description": .string("時間視窗（分鐘），預設 60")
                        ])
                    ]),
                    "required": .array([.string("station_id"), .string("system")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "rail_route",
                description: "查 TRA 時刻表 O/D 路由：給起站、迄站、（可選）最早出發時間，在當日真實時刻表上算最早抵達 itinerary，並套用即時誤點（TrainLiveBoard）調整——表訂最早的車若誤點，可能改回較晚但實際更早到的車。回 legs（每段：車次、起訖站、開/到時刻、誤點分、source: live|scheduled）+ arrival_time + duration_min。與 rail_find_trains（列全部班次）用途不同。僅支援 TRA。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object([
                            "type": .string("string"),
                            "description": .string("起站 ID（用 rail_search_stations 查詢）")
                        ]),
                        "to": .object([
                            "type": .string("string"),
                            "description": .string("迄站 ID（用 rail_search_stations 查詢）")
                        ]),
                        "depart_after": .object([
                            "type": .string("string"),
                            "description": .string("最早出發時間 HH:mm（Asia/Taipei，預設現在）")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("鐵路系統代碼，僅支援 TRA（預設 TRA）"),
                            "enum": .array([.string("TRA")])
                        ])
                    ]),
                    "required": .array([.string("from"), .string("to")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
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
            case "rail_list_systems":
                return try await executeListSystems()
            case "rail_find_trains":
                return try await executeFindTrains(arguments: arguments, client: client, cache: cache)
            case "rail_search_stations":
                return try await executeSearchStations(arguments: arguments, client: client, cache: cache)
            case "rail_status_train":
                return try await executeStatusTrain(arguments: arguments, client: client, cache: cache)
            case "rail_status_station":
                return try await executeStatusStation(arguments: arguments, client: client, cache: cache)
            case "rail_route":
                return try await executeRoute(arguments: arguments, client: client, cache: cache)
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
        return ToolResult.json(["systems": systems])
    }

    private static func executeFindTrains(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let from = arguments["from"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: from")
        }
        guard let to = arguments["to"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: to")
        }
        let date = try validateDate(arguments["date"]?.stringValue ?? "")
        guard let sysCode = arguments["system"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: system")
        }
        guard let sys = RailSystem(rawValue: sysCode) else {
            throw TDXError.decoding("Invalid system '\(sysCode)'. Use rail_list_systems to see valid codes.")
        }
        guard sys == .TRA || sys == .THSR else {
            throw TDXError.decoding("system must be TRA or THSR for rail_find_trains (metros use station-based queries)")
        }

        let path = TDXEndpoints.railTimetableOD(sys, from: from, to: to, date: date)
        let data = try await client.fetch(
            path: path,
            cacheTTL: 3600,
            cache: cache
        )

        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    private static func executeStatusTrain(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let trainNo = arguments["train_no"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: train_no")
        }
        guard let sysCode = arguments["system"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: system")
        }
        guard let sys = RailSystem(rawValue: sysCode) else {
            throw TDXError.decoding("Invalid system '\(sysCode)'. Use rail_list_systems.")
        }
        guard sys == .TRA else {
            throw TDXError.decoding("system must be TRA for rail_status_train (TDX provides no THSR live board)")
        }

        // v3 filters the live-board collection by query, not a /Train/{no} path segment.
        let data = try await client.fetch(
            path: TDXEndpoints.railTrainLiveBoard(),
            queryItems: [URLQueryItem(name: "$filter", value: "TrainNo eq '\(trainNo)'")],
            cacheTTL: 0,  // live data — do not cache
            cache: cache
        )
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    private static func executeStatusStation(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let stationID = arguments["station_id"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: station_id")
        }
        guard let sysCode = arguments["system"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: system")
        }
        guard let sys = RailSystem(rawValue: sysCode) else {
            throw TDXError.decoding("Invalid system '\(sysCode)'. Use rail_list_systems.")
        }
        guard sys == .TRA else {
            throw TDXError.decoding("system must be TRA for rail_status_station (TDX provides no THSR live board)")
        }

        // window_min is currently informational (TDX endpoint returns a default window);
        // it's accepted in the schema but does not change the path. Future enhancement could
        // filter the result client-side.

        let path = TDXEndpoints.railStationLiveBoard(stationID: stationID)
        let data = try await client.fetch(
            path: path,
            cacheTTL: 0,  // live data
            cache: cache
        )
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
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

        // Fan out per-system station fetches in parallel. Cold-cache cost drops from
        // ~Nx sequential RTTs to one. Cache hits short-circuit inside fetch(), so
        // steady-state is unaffected. 8 parallel requests sits well under TDX's 50/min.
        let perSystemResults = try await withThrowingTaskGroup(of: (RailSystem, [RailStation]).self) { group in
            for sys in systemFilter {
                group.addTask {
                    let data = try await client.fetch(
                        path: TDXEndpoints.railStation(sys),
                        cacheTTL: 86400,
                        cache: cache
                    )
                    return (sys, Self.decodeStationList(data: data))
                }
            }
            var collected: [(RailSystem, [RailStation])] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        // Stable ordering: TaskGroup completion order is non-deterministic, so re-sort
        // by RailSystem.allCases index so the LLM sees consistent output across calls.
        let orderIndex = Dictionary(uniqueKeysWithValues: RailSystem.allCases.enumerated().map { ($1, $0) })
        let ordered = perSystemResults.sorted { (orderIndex[$0.0] ?? 0) < (orderIndex[$1.0] ?? 0) }

        var allMatches: [[String: Any]] = []
        for (sys, stations) in ordered {
            for m in Self.fuzzyMatch(query: query, in: stations) {
                allMatches.append([
                    "system": sys.rawValue,
                    "station_id": m.stationID,
                    "name_zh": m.stationName.zhTw ?? "",
                    "name_en": m.stationName.en ?? ""
                ])
            }
        }

        return ToolResult.json(["matches": allMatches])
    }
}

// MARK: - Date validation

extension RailTools {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()

    static func validateDate(_ s: String) throws -> String {
        // Strict check: parse then re-format and compare to ensure exact YYYY-MM-DD shape
        guard let parsed = dateFormatter.date(from: s),
              dateFormatter.string(from: parsed) == s else {
            throw TDXError.decoding("Invalid date '\(s)'. Use ISO format YYYY-MM-DD.")
        }
        return s
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

// MARK: - rail_route: TRA time-dependent earliest-arrival routing (#6 Stage 1)

extension RailTools {

    /// Build the TRA timetable graph (DailyTrainTimetable OD), apply live train
    /// delays (TrainLiveBoard), and return the live-adjusted earliest-arrival
    /// itinerary. Both data sources arrive wrapped; `TDXDecode.list` unwraps them.
    /// Graceful: timetable unavailable → empty + note; live board unavailable →
    /// all legs scheduled. Empty ≠ error.
    static func executeRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let from = arguments["from"]?.stringValue, !from.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from")
        }
        guard let to = arguments["to"]?.stringValue, !to.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to")
        }
        if let sysCode = arguments["system"]?.stringValue, sysCode != "TRA" {
            throw TDXError.decoding("rail_route 目前僅支援 TRA（唯一同時有時刻表與即時誤點的系統）；其他系統規劃中")
        }

        let departAfterMin: Int = {
            if let s = arguments["depart_after"]?.stringValue, let m = TimetableRouter.minutesOfDay(s) { return m }
            return nowMinutesTaipei()
        }()
        let departAfter = TimetableRouter.clock(departAfterMin)
        let date = dateFormatter.string(from: Date())

        // Timetable (static, 1h cache). Graceful on TDX failure — empty + note.
        let trains: [RailODFare]
        do {
            let odData = try await client.fetch(
                path: TDXEndpoints.railTimetableOD(.TRA, from: from, to: to, date: date),
                cacheTTL: 3600, cache: cache)
            trains = TDXDecode.list(RailODFare.self, from: odData)
        } catch {
            return ToolResult.json(["from": from, "to": to, "system": "TRA", "depart_after": departAfter,
                                "legs": [[String: Any]](),
                                "note": "TRA 時刻表暫時無法取得（TDX 端問題）：\(error.localizedDescription)"])
        }
        if trains.isEmpty {
            return ToolResult.json(["from": from, "to": to, "system": "TRA", "depart_after": departAfter,
                                "legs": [[String: Any]](),
                                "note": "查無 \(from) → \(to) 的當日 TRA 班次"])
        }

        // Live delays (live, no cache). Graceful: unavailable → empty → all scheduled.
        var delays: [String: Int] = [:]
        if let lbData = try? await client.fetch(path: TDXEndpoints.railTrainLiveBoard(), cacheTTL: 0, cache: cache) {
            for t in TDXDecode.list(RailLiveTrain.self, from: lbData) {
                if let d = t.delayTime { delays[t.trainNo] = d }
            }
        }

        let conns = TimetableRouter.connections(from: trains, delays: delays)
        guard let itinerary = TimetableRouter.earliestArrival(
            connections: conns, from: from, to: to, departAfterMin: departAfterMin) else {
            return ToolResult.json(["from": from, "to": to, "system": "TRA", "depart_after": departAfter,
                                "legs": [[String: Any]](),
                                "note": "\(departAfter) 之後查無可達 \(to) 的班次"])
        }

        let legs: [[String: Any]] = itinerary.legs.map { leg in
            ["train_no": leg.trainNo,
             "from_station_id": leg.fromStation, "from_name": leg.fromName,
             "to_station_id": leg.toStation, "to_name": leg.toName,
             "dep_time": TimetableRouter.clock(leg.depMin),
             "arr_time": TimetableRouter.clock(leg.arrMin),
             "delay_min": leg.delayMin,
             "source": leg.live ? "live" : "scheduled"]
        }
        let boardMin = itinerary.legs.first?.depMin ?? departAfterMin
        return ToolResult.json([
            "from": from, "to": to, "system": "TRA", "depart_after": departAfter,
            "arrival_time": TimetableRouter.clock(itinerary.arrMin),
            "duration_min": itinerary.arrMin - boardMin,
            "transfer_count": max(0, itinerary.legs.count - 1),
            "legs": legs
        ])
    }

    private static func nowMinutesTaipei() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
    }
}
