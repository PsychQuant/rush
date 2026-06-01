// Sources/CheTransportMCP/Tools/TransitTools.swift
import Foundation
import MCP

/// `transit_route` — Stage 2 multi-modal TRA↔Taipei-Metro routing.
///
/// Orchestration only: resolves the endpoints across both systems, fetches the
/// TRA timetable (via the 台北車站 hub) + metro datasets, then hands everything to
/// `MultimodalRouter` for the time-anchored composition. The routing logic lives
/// in `MultimodalRouter`; this file is the I/O + formatting boundary.
enum TransitTools {

    /// Hub interchange whose OD timetable covers the in-between interchanges.
    private static let hubTRAStationID = "1000"   // 臺北

    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "transit_route",
                description: "TRA↔台北捷運多模式路由：給起站、迄站（可跨台鐵/捷運），算出 depart_after（預設現在）起最早抵達的行程。回 legs（每段 mode=TRA/Metro、起訖站、時刻、source=live/scheduled/frequency）、transfers（交會站 + 步行分鐘）、arrival_time、duration_min、transfer_count。捷運段按班距估期望等車（headway/2，source=frequency）；台鐵段含即時誤點（source=live）。僅支援 TRA + 台北捷運（TRTC），且跨系統轉乘僅限策劃的交會站（台北車站/板橋/南港/松山）。站名多系統同名時回 matches 供釐清。查無路徑回空 routes + note（非錯誤）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object(["type": .string("string"), "description": .string("起站（站名或站 ID，可為台鐵或台北捷運站）")]),
                        "to": .object(["type": .string("string"), "description": .string("迄站（站名或站 ID）")]),
                        "depart_after": .object(["type": .string("string"), "description": .string("出發時間錨點 HH:mm（Asia/Taipei），預設現在")])
                    ]),
                    "required": .array([.string("from"), .string("to")])
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
            case "transit_route":
                return try await executeRoute(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    // MARK: - Executor

    static func executeRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let fromQ = arguments["from"]?.stringValue, !fromQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from")
        }
        guard let toQ = arguments["to"]?.stringValue, !toQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to")
        }
        let departAfterMin: Int = {
            if let s = arguments["depart_after"]?.stringValue, let m = TimetableRouter.minutesOfDay(s) { return m }
            return nowMinutesTaipei()
        }()
        let departAfter = TimetableRouter.clock(departAfterMin)

        // (1) TRA station list + (2) metro StationOfRoute — both for endpoint resolution.
        let traStations: [RailStation] = TDXDecode.list(
            RailStation.self, from: try await client.fetch(path: TDXEndpoints.railStation(.TRA), cacheTTL: 86400, cache: cache))
        let metroSOR: [MetroStationOfRoute] = (try? JSONDecoder().decode(
            [MetroStationOfRoute].self, from: try await client.fetch(path: TDXEndpoints.metroStationOfRoute(.TRTC), cacheTTL: 86400, cache: cache))) ?? []
        let metroStations = uniqueMetroStations(metroSOR)

        // (3) Resolve endpoints. Ambiguous → matches; not found → note.
        let fromMatches = resolveCandidates(fromQ, traStations: traStations, metroStations: metroStations)
        let toMatches = resolveCandidates(toQ, traStations: traStations, metroStations: metroStations)
        if let amb = disambiguation(query: fromQ, role: "from", matches: fromMatches, departAfter: departAfter) { return amb }
        if let amb = disambiguation(query: toQ, role: "to", matches: toMatches, departAfter: departAfter) { return amb }
        let from = fromMatches[0], to = toMatches[0]

        // (4-6) Remaining metro datasets for the graph.
        let s2s: [MetroS2STravelTime] = (try? JSONDecoder().decode(
            [MetroS2STravelTime].self, from: try await client.fetch(path: TDXEndpoints.metroS2STravelTime(.TRTC), cacheTTL: 86400, cache: cache))) ?? []
        let frequency: [MetroFrequency] = (try? JSONDecoder().decode(
            [MetroFrequency].self, from: try await client.fetch(path: TDXEndpoints.metroFrequency(.TRTC), cacheTTL: 86400, cache: cache))) ?? []
        var lineTransfer: [MetroLineTransfer] = []
        if let ltData = try? await client.fetch(path: TDXEndpoints.metroLineTransfer(.TRTC), cacheTTL: 86400, cache: cache) {
            lineTransfer = (try? JSONDecoder().decode([MetroLineTransfer].self, from: ltData)) ?? []
        }
        let metroData = MultimodalRouter.MetroData(
            stationOfRoute: metroSOR, s2s: s2s, lineTransfer: lineTransfer, frequency: frequency)

        // (7-8) TRA timetable (only when a TRA leg is possible), graceful on outage.
        var traConnections: [TimetableRouter.Connection] = []
        if from.mode == .tra || to.mode == .tra {
            let odFrom = (from.mode == .tra) ? from.primaryID : hubTRAStationID
            let odTo = (to.mode == .tra) ? to.primaryID : hubTRAStationID
            let trains: [RailODFare]
            do {
                let odData = try await client.fetch(
                    path: TDXEndpoints.railTimetableOD(.TRA, from: odFrom, to: odTo, date: todayString()),
                    cacheTTL: 3600, cache: cache)
                trains = TDXDecode.list(RailODFare.self, from: odData)
            } catch {
                return emptyRoutes(from: from, to: to, departAfter: departAfter,
                                   note: "TRA 時刻表暫時無法取得（TDX 端問題）：\(error.localizedDescription)")
            }
            if trains.isEmpty {
                return emptyRoutes(from: from, to: to, departAfter: departAfter,
                                   note: "查無 \(from.name) → \(to.name) 路段的當日 TRA 班次（台鐵段無法銜接）")
            }
            var delays: [String: Int] = [:]
            if let lbData = try? await client.fetch(path: TDXEndpoints.railTrainLiveBoard(), cacheTTL: 0, cache: cache) {
                for t in TDXDecode.list(RailLiveTrain.self, from: lbData) {
                    if let d = t.delayTime { delays[t.trainNo] = d }
                }
            }
            traConnections = TimetableRouter.connections(from: trains, delays: delays)
        }

        // Compose.
        guard let it = MultimodalRouter.route(
            from: from, to: to, departAfterMin: departAfterMin,
            traConnections: traConnections, metro: metroData, queryDate: Date()) else {
            return emptyRoutes(from: from, to: to, departAfter: departAfter,
                               note: "\(departAfter) 之後查無可達路徑（可能起迄站不在 TRA↔台北捷運的可達範圍，或跨系統無策劃交會站銜接）")
        }

        return ToolResult.json(routePayload(from: from, to: to, departAfter: departAfter, itinerary: it))
    }

    // MARK: - Endpoint resolution

    /// Logical station candidates matching `query` across TRA and TRTC. Metro
    /// nodes sharing a station name (an interchange's per-line platforms, e.g.
    /// 西門 = BL11 + G12) collapse into ONE logical stop carrying all node ids —
    /// they are not a disambiguation choice. Exact-id or exact-name wins over a
    /// substring match. More than one *distinct* logical station → ambiguous.
    static func resolveCandidates(_ query: String, traStations: [RailStation],
                                  metroStations: [(id: String, name: String)]) -> [MultimodalRouter.Stop] {
        // Exact id (returns the single logical station; for metro, all same-name platforms).
        if let s = traStations.first(where: { $0.stationID == query }) {
            return [.init(mode: .tra, ids: [s.stationID], name: s.stationName.zhTw ?? s.stationID)]
        }
        if let m = metroStations.first(where: { $0.id == query }) {
            let ids = metroStations.filter { $0.name == m.name }.map { $0.id }
            return [.init(mode: .metro, ids: ids, name: m.name)]
        }

        let q = normalize(query)
        // Exact name preferred; fall back to substring only when no exact hit.
        var traMatches = traStations.filter { normalize($0.stationName.zhTw ?? "") == q }
        var metroMatches = metroStations.filter { normalize($0.name) == q }
        if traMatches.isEmpty && metroMatches.isEmpty {
            traMatches = RailTools.fuzzyMatch(query: query, in: traStations)
            metroMatches = metroStations.filter { normalize($0.name).contains(q) }
        }

        var stops: [MultimodalRouter.Stop] = []
        // TRA: one logical stop per distinct (normalized) name.
        var seenTRA: Set<String> = []
        for s in traMatches {
            let nm = s.stationName.zhTw ?? s.stationID
            if seenTRA.insert(normalize(nm)).inserted {
                stops.append(.init(mode: .tra, ids: [s.stationID], name: nm))
            }
        }
        // Metro: group node ids by name → one logical stop per station.
        var byName: [String: (name: String, ids: [String])] = [:]
        var order: [String] = []
        for m in metroMatches {
            let key = normalize(m.name)
            if byName[key] == nil { byName[key] = (m.name, []); order.append(key) }
            byName[key]!.ids.append(m.id)
        }
        for key in order {
            let g = byName[key]!
            stops.append(.init(mode: .metro, ids: g.ids, name: g.name))
        }
        return stops
    }

    private static func disambiguation(query: String, role: String,
                                       matches: [MultimodalRouter.Stop], departAfter: String) -> CallTool.Result? {
        if matches.isEmpty {
            return ToolResult.json(["from_query": query, "depart_after": departAfter, "routes": [[String: Any]](),
                                    "note": "查無 \(role) 站「\(query)」（台鐵與台北捷運皆無相符站名／站 ID）"])
        }
        if matches.count > 1 {
            return ToolResult.json([
                "ambiguous": role, "query": query,
                "matches": matches.map { ["system": $0.mode.rawValue, "station_ids": $0.ids, "name": $0.name] },
                "note": "「\(query)」對應多個站，請改用明確站 ID 或更精確站名"])
        }
        return nil
    }

    private static func uniqueMetroStations(_ sor: [MetroStationOfRoute]) -> [(id: String, name: String)] {
        var seen: Set<String> = []
        var out: [(id: String, name: String)] = []
        for r in sor {
            for st in r.stations where !seen.contains(st.stationID) {
                seen.insert(st.stationID)
                out.append((id: st.stationID, name: st.stationName.zhTw ?? st.stationID))
            }
        }
        return out
    }

    /// Fold 臺→台 so cross-system spelling (台鐵 臺北 vs 捷運 台北) matches.
    private static func normalize(_ s: String) -> String { s.replacingOccurrences(of: "臺", with: "台") }

    // MARK: - Output

    private static func emptyRoutes(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop,
                                    departAfter: String, note: String) -> CallTool.Result {
        ToolResult.json([
            "from": from.name, "to": to.name, "depart_after": departAfter,
            "routes": [[String: Any]](), "note": note])
    }

    private static func routePayload(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop,
                                     departAfter: String, itinerary it: MultimodalRouter.Itinerary) -> [String: Any] {
        let legs: [[String: Any]] = it.legs.map { leg in
            var d: [String: Any] = [
                "mode": leg.mode.rawValue, "line": leg.line,
                "from_station_id": leg.fromStation, "from_name": leg.fromName,
                "to_station_id": leg.toStation, "to_name": leg.toName,
                "dep_time": TimetableRouter.clock(leg.depMin),
                "arr_time": TimetableRouter.clock(leg.arrMin),
                "source": leg.source]
            if let dm = leg.delayMin { d["delay_min"] = dm }
            return d
        }
        let transfers: [[String: Any]] = it.transfers.map {
            ["at": $0.at, "at_name": $0.atName, "walk_min": $0.walkMin]
        }
        let boardMin = it.legs.first?.depMin ?? it.arrMin
        return [
            "from": from.name, "to": to.name, "depart_after": departAfter,
            "arrival_time": TimetableRouter.clock(it.arrMin),
            "duration_min": max(0, it.arrMin - boardMin),
            "transfer_count": it.transferCount,
            "legs": legs, "transfers": transfers]
    }

    // MARK: - Time helpers

    private static func nowMinutesTaipei() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let now = Date()
        return cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
