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
            ),
            Tool(
                name: "rail_bus_route",
                description: "鐵路→公車多模式路由（Stage 3b，需明確指定轉乘站）：給起站 from、轉乘鐵路站 transfer、公車迄站 to_stop 與 city，算出 depart_after（預設現在）起最早抵達的 rail→步行→bus 行程。鐵路段用 transit_route 的 TRA↔台北捷運引擎（source=live/scheduled/frequency），於 transfer 站以站名比對（捷運X站／X車站）找出公車上車站，公車段以「抵達 transfer + 步行」為發車錨點算直達 to_stop 的班次（A2 即時不適用未來時刻故停用，改用班表發車 source:scheduled／班距期望 source:frequency；班表抵達 source:scheduled，frequency-only 抵達從缺 + note）。回 legs（鐵路各段 + 一段 bus）、transfers（transfer 站 + 步行分鐘，步行為估計值）、arrival_time、duration_min、transfer_count(=1)。起/transfer/to_stop 站名多筆同名 → 回 matches。鐵路不可達／transfer 無對應公車上車站／無直達 to_stop → routes:[] + note（非錯誤）。僅 rail→bus 單轉乘；自動選轉乘站、bus→rail、多段轉乘為未來工作（3b-ii）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object(["type": .string("string"), "description": .string("起站（站名或站 ID，台鐵或台北捷運站）")]),
                        "transfer": .object(["type": .string("string"), "description": .string("轉乘的鐵路站（站名或站 ID，台鐵或台北捷運站）——在此站由鐵路換乘公車")]),
                        "to_stop": .object(["type": .string("string"), "description": .string("公車迄站站名或 StopUID")]),
                        "city": .object(["type": .string("string"), "description": .string("公車城市代碼（BusCity 列舉，如 Taipei）"), "enum": .array(BusCity.allCases.map { .string($0.rawValue) })]),
                        "depart_after": .object(["type": .string("string"), "description": .string("出發時間錨點 HH:mm（Asia/Taipei），預設現在")])
                    ]),
                    "required": .array([.string("from"), .string("transfer"), .string("to_stop"), .string("city")]),
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
            case "transit_route":
                return try await executeRoute(arguments: arguments, client: client, cache: cache)
            case "rail_bus_route":
                return try await executeRailBusRoute(arguments: arguments, client: client, cache: cache)
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

    // MARK: - Stage 3b: rail → bus

    /// `rail_bus_route` — rail leg (`MultimodalRouter`) to an explicit `transfer`
    /// station, then a name-matched bus leg (`BusRouter`, A2 disabled) to `to_stop`.
    /// Orchestration only; the stitch lives in `RailBusRouter`. Auto-hub selection,
    /// bus→rail, and multi-transfer are out of scope (3b-ii).
    static func executeRailBusRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let fromQ = arguments["from"]?.stringValue, !fromQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from")
        }
        guard let transferQ = arguments["transfer"]?.stringValue, !transferQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: transfer")
        }
        guard let toQ = arguments["to_stop"]?.stringValue, !toQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to_stop")
        }
        let city = try BusTools.parseCity(arguments)
        let nowMin = nowMinutesTaipei()
        let weekday = railBusWeekdayTaipei()
        let departAfterMin = arguments["depart_after"]?.stringValue.flatMap(TimetableRouter.minutesOfDay) ?? nowMin
        let departAfter = TimetableRouter.clock(departAfterMin)

        // Rail endpoints: from + transfer (reuse transit_route resolution; TRA+TRTC).
        let traStations: [RailStation] = TDXDecode.list(
            RailStation.self, from: try await client.fetch(path: TDXEndpoints.railStation(.TRA), cacheTTL: 86400, cache: cache))
        let metroSOR: [MetroStationOfRoute] = (try? JSONDecoder().decode(
            [MetroStationOfRoute].self, from: try await client.fetch(path: TDXEndpoints.metroStationOfRoute(.TRTC), cacheTTL: 86400, cache: cache))) ?? []
        let metroStations = uniqueMetroStations(metroSOR)
        let fromMatches = resolveCandidates(fromQ, traStations: traStations, metroStations: metroStations)
        let transferMatches = resolveCandidates(transferQ, traStations: traStations, metroStations: metroStations)
        if let amb = disambiguation(query: fromQ, role: "from", matches: fromMatches, departAfter: departAfter) { return amb }
        if let amb = disambiguation(query: transferQ, role: "transfer", matches: transferMatches, departAfter: departAfter) { return amb }
        let from = fromMatches[0], transfer = transferMatches[0]

        // Bus stops + resolve to_stop (name or StopUID; ambiguous → matches).
        let busStops = BusTools.decodeList(BusStop.self, data: try await client.fetch(
            path: TDXEndpoints.busStop(city.rawValue), cacheTTL: 86400, cache: cache))
        let to: (uid: String, name: String)
        switch resolveBusStop(toQ, stops: busStops, city: city, departAfter: departAfter) {
        case .one(let u, let n): to = (u, n)
        case .result(let r): return r
        }

        // Rail leg from → transfer.
        let railIt: MultimodalRouter.Itinerary
        switch try await composeRailLeg(from: from, to: transfer, departAfterMin: departAfterMin,
                                        metroSOR: metroSOR, client: client, cache: cache) {
        case .ok(let it): railIt = it
        case .empty(let note):
            return railBusEmpty(from: from.name, transfer: transfer.name, toName: to.name,
                                city: city, departAfter: departAfter, note: "鐵路段：\(note)")
        }
        let transferWalkMin = RailBusRouter.defaultTransferWalkMin
        let busDepartAfterMin = railIt.arrMin + transferWalkMin

        // Name-matched boarding stops at the transfer station.
        let candidateStops = busStops.filter {
            RailBusRouter.busStopMatchesStation(stopName: $0.stopName.zhTw ?? "", stationName: transfer.name) }
        if candidateStops.isEmpty {
            return railBusEmpty(from: from.name, transfer: transfer.name, toName: to.name, city: city, departAfter: departAfter,
                                note: "於 \(transfer.name) 查無對應的公車上車站（站名比對 捷運X站／X車站 無結果）；可能 \(city.rawValue) 非該站所在城市")
        }
        let candidateUIDs = Set(candidateStops.map { $0.stopUID })

        // Candidate direct bus routes: a name-matched stop before to_stop, same direction.
        let routes = BusTools.decodeList(BusStopOfRoute.self, data: try await client.fetch(
            path: TDXEndpoints.busStopOfRoute(city.rawValue), cacheTTL: 3600, cache: cache))
        var candidates: [BusRouter.Candidate] = []
        for r in routes {
            guard let di = r.stops.firstIndex(where: { $0.stopUID == to.uid }) else { continue }
            guard let oi = r.stops.indices.first(where: { candidateUIDs.contains(r.stops[$0].stopUID) && $0 < di }) else { continue }
            candidates.append(.init(
                routeUID: r.routeUID, routeName: r.routeName.zhTw ?? r.routeUID, subRouteName: nil,
                direction: r.direction ?? 0,
                originStopUID: r.stops[oi].stopUID, originStopName: r.stops[oi].stopName.zhTw ?? "",
                destStopUID: to.uid, destStopName: r.stops[di].stopName.zhTw ?? to.name))
        }
        if candidates.isEmpty {
            return railBusEmpty(from: from.name, transfer: transfer.name, toName: to.name, city: city, departAfter: departAfter,
                                note: "於 \(transfer.name) 的公車上車站查無直達 \(to.name) 的路線；多段公車轉乘尚未支援（3b-ii）")
        }

        // Bus leg: A2 DISABLED (a now-snapshot cannot time a future post-transfer board);
        // board from schedule/headway only, anchored at rail arrival + walk.
        var scheduleBySig: [String: BusSchedule] = [:]
        if let sc = try? await client.fetch(path: TDXEndpoints.busSchedule(city.rawValue), cacheTTL: 3600, cache: cache) {
            for s in BusTools.decodeList(BusSchedule.self, data: sc) {
                let k = BusRouter.sig(s.routeUID, s.direction ?? 0)
                if scheduleBySig[k] == nil { scheduleBySig[k] = s }
            }
        }
        let options = BusRouter.route(candidates: candidates, a2BySig: [:], scheduleBySig: scheduleBySig,
                                      nowMin: nowMin, departAfterMin: busDepartAfterMin, weekday: weekday)
        guard let composed = RailBusRouter.compose(railLegs: railIt.legs, transferStationName: transfer.name,
                                                   transferWalkMin: transferWalkMin, busOptions: options, nowMin: nowMin) else {
            return railBusEmpty(from: from.name, transfer: transfer.name, toName: to.name, city: city, departAfter: departAfter,
                                note: "於 \(transfer.name) 查無從上車站直達 \(to.name) 的可組合班次")
        }
        return ToolResult.json(railBusPayload(fromName: from.name, transfer: transfer, toName: to.name,
                                              city: city, departAfter: departAfter, result: composed))
    }

    /// Fetch the metro datasets (reusing the already-fetched `metroSOR`) + the TRA OD
    /// timetable, then compose the rail leg `from → to` via `MultimodalRouter`. Returns
    /// the itinerary, or a note explaining why no rail path exists (graceful, never errors
    /// on data gaps). Mirrors `executeRoute`'s fetch block so `transit_route` stays frozen.
    /// Outcome of the rail-leg composition: a reachable itinerary, or a note string.
    private enum RailLegOutcome { case ok(MultimodalRouter.Itinerary); case empty(String) }

    private static func composeRailLeg(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop,
                                       departAfterMin: Int, metroSOR: [MetroStationOfRoute],
                                       client: TDXClient, cache: Cache) async throws -> RailLegOutcome {
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
                return .empty("時刻表暫時無法取得（TDX 端問題）：\(error.localizedDescription)")
            }
            if trains.isEmpty {
                return .empty("查無 \(from.name) → \(to.name) 路段的當日 TRA 班次（台鐵段無法銜接）")
            }
            var delays: [String: Int] = [:]
            if let lbData = try? await client.fetch(path: TDXEndpoints.railTrainLiveBoard(), cacheTTL: 0, cache: cache) {
                for t in TDXDecode.list(RailLiveTrain.self, from: lbData) {
                    if let d = t.delayTime { delays[t.trainNo] = d }
                }
            }
            traConnections = TimetableRouter.connections(from: trains, delays: delays)
        }
        guard let it = MultimodalRouter.route(
            from: from, to: to, departAfterMin: departAfterMin,
            traConnections: traConnections, metro: metroData, queryDate: Date()) else {
            return .empty("查無可達路徑（起站與轉乘站可能不在 TRA↔台北捷運可達範圍，或跨系統無策劃交會站銜接）")
        }
        return .ok(it)
    }

    private enum BusStopPick { case one(uid: String, name: String); case result(CallTool.Result) }

    /// to_stop resolution for rail_bus_route: exact StopUID, else fuzzy by name (reusing
    /// `BusTools.fuzzyMatchStops`). One physical stop → `.one`; none/multiple → a ready
    /// result (note / matches).
    private static func resolveBusStop(_ q: String, stops: [BusStop], city: BusCity, departAfter: String) -> BusStopPick {
        if let s = stops.first(where: { $0.stopUID == q }) {
            return .one(uid: s.stopUID, name: s.stopName.zhTw ?? s.stopUID)
        }
        let matched = BusTools.fuzzyMatchStops(query: q, in: stops)
        if matched.isEmpty {
            return .result(ToolResult.json([
                "query": q, "role": "to_stop", "city": city.rawValue, "depart_after": departAfter,
                "routes": [[String: Any]](), "note": "查無 to_stop 站「\(q)」"]))
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
            "ambiguous": "to_stop", "query": q, "city": city.rawValue, "matches": Array(ms),
            "note": "「\(q)」對應多個站牌，請改用 StopUID 或更精確站名"]))
    }

    private static func railBusEmpty(from: String, transfer: String, toName: String,
                                     city: BusCity, departAfter: String, note: String) -> CallTool.Result {
        ToolResult.json([
            "from": from, "transfer": transfer, "to_stop": toName, "city": city.rawValue,
            "depart_after": departAfter, "routes": [[String: Any]](), "note": note])
    }

    private static func railBusWeekdayTaipei() -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return cal.component(.weekday, from: Date())
    }

    private static func railBusPayload(fromName: String, transfer: MultimodalRouter.Stop, toName: String,
                                       city: BusCity, departAfter: String, result composed: RailBusRouter.Result) -> [String: Any] {
        var legs: [[String: Any]] = composed.railLegs.map { leg in
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
        let bus = composed.bus
        var busLeg: [String: Any] = [
            "mode": "Bus", "line": bus.routeName, "direction": bus.direction,
            "from_name": bus.boardStop, "to_name": toName,
            "dep_time": TimetableRouter.clock(composed.busBoardClockMin),
            "source": bus.boardSource]
        if let sub = bus.subRouteName { busLeg["sub_route_name"] = sub }
        if let at = bus.arrivalTime {
            busLeg["arr_time"] = at; busLeg["arrival_source"] = bus.arrivalSource ?? "scheduled"
        } else {
            busLeg["arr_time"] = NSNull()
        }
        if let n = bus.note { busLeg["note"] = n }
        legs.append(busLeg)

        let transfers: [[String: Any]] = [[
            "at": transfer.primaryID, "at_name": transfer.name, "walk_min": composed.transferWalkMin,
            "note": "步行分鐘為估計值（上車站位於 \(transfer.name) 站）"]]

        let boardMin = composed.railLegs.first?.depMin ?? composed.busBoardClockMin
        var payload: [String: Any] = [
            "from": fromName, "transfer": transfer.name, "to_stop": toName, "city": city.rawValue,
            "depart_after": departAfter, "transfer_count": 1, "legs": legs, "transfers": transfers]
        if let arr = composed.arrivalClockMin {
            payload["arrival_time"] = TimetableRouter.clock(arr)
            payload["duration_min"] = max(0, arr - boardMin)
        } else {
            payload["arrival_time"] = NSNull()
            payload["note"] = "公車段為班距期望班次（frequency），抵達時刻從缺、不假裝精確"
        }
        return payload
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
