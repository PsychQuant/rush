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
                description: "鐵路→公車多模式路由（Stage 3b）：給起站 from、公車迄站 to_stop 與 city，算出 depart_after（預設現在）起最早抵達的 rail→步行→bus 行程。transfer 轉乘鐵路站為**選填**：指定時走該站轉乘（3b-i）；省略時自動選交會站（3b-ii）——以 to_stop 為錨反向搜尋（serving to_stop 的公車路線上游站做站名比對 捷運X站／X車站 找出對應鐵路站），對每個候選交會站跑 rail+bus 並回最早抵達者，輸出 auto_selected_transfer 標示選中的交會站（候選數有上限，超過會在 note 揭露捨棄數）。鐵路段用 transit_route 的 TRA↔台北捷運引擎（source=live/scheduled/frequency）；公車段以「抵達 transfer + 步行」為發車錨點算直達 to_stop 的班次（A2 即時不適用未來時刻故停用，改用班表發車 source:scheduled／班距期望 source:frequency；班表抵達 source:scheduled，frequency-only 抵達從缺 + note）。回 legs（鐵路各段 + 一段 bus）、transfers（transfer 站 + 步行分鐘，步行為估計值）、arrival_time、duration_min、transfer_count(=1)。站名多筆同名 → 回 matches。鐵路不可達／無對應公車上車站／無直達 to_stop → routes:[] + note（非錯誤）。僅 rail→bus 單轉乘；bus→rail、多段轉乘為未來工作（3c）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object(["type": .string("string"), "description": .string("起站（站名或站 ID，台鐵或台北捷運站）")]),
                        "transfer": .object(["type": .string("string"), "description": .string("（選填）轉乘的鐵路站（站名或站 ID，台鐵或台北捷運站）——指定則於該站換乘；省略則自動選交會站")]),
                        "to_stop": .object(["type": .string("string"), "description": .string("公車迄站站名或 StopUID")]),
                        "city": .object(["type": .string("string"), "description": .string("公車城市代碼（BusCity 列舉，如 Taipei）"), "enum": .array(BusCity.allCases.map { .string($0.rawValue) })]),
                        "depart_after": .object(["type": .string("string"), "description": .string("出發時間錨點 HH:mm（Asia/Taipei），預設現在")])
                    ]),
                    "required": .array([.string("from"), .string("to_stop"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bus_rail_route",
                description: "公車→鐵路多模式路由（Stage 3c-i）：給公車起站 from_stop、鐵路迄站 to（台鐵或台北捷運站）與 city，算出 depart_after（預設現在）起最早抵達的 bus→步行→rail 行程。公車段為 leg 1、上車在旅程起點故 **A2 即時可用**（source:live；無則班表發車 source:scheduled／班距期望 source:frequency）。`transfer` 鐵路交會站**選填**：給定時於該站下車轉乘；省略時自動選下車站——以 from_stop 為錨正向搜尋（serving from_stop 的公車路線，對 from_stop 下游站做站名比對找鐵路站），對候選下車站跑 bus+rail 取最早抵達，輸出 auto_selected_transfer；候選有上限（預設 8），超過於 auto_hub_note 揭露捨棄數。鐵路段用 transit_route 引擎，以「公車抵達交會站 + 步行」為 departAfter；**公車抵達未知時（frequency-only）改以上車時刻+步行錨定 rail 並加近似 note，不假裝精確**。回 legs（一段 Bus + 鐵路各段）+ transfers（交會站 + walk_min，步行為估計值）+ arrival_time（rail 抵達）+ duration_min + transfer_count(=1)。from_stop／to 多筆同名 → matches；無對應下車站／rail 不可達／無直達 bus → routes:[] + note（非錯誤）。僅 bus→rail 單轉乘；multi-transfer／統一 RAPTOR 核心為未來工作。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from_stop": .object(["type": .string("string"), "description": .string("公車起站站名或 StopUID")]),
                        "to": .object(["type": .string("string"), "description": .string("鐵路迄站（站名或站 ID，台鐵或台北捷運站）")]),
                        "city": .object(["type": .string("string"), "description": .string("公車城市代碼（BusCity 列舉，如 Taipei）"), "enum": .array(BusCity.allCases.map { .string($0.rawValue) })]),
                        "transfer": .object(["type": .string("string"), "description": .string("（選填）下車轉乘的鐵路站；省略則自動選下車站")]),
                        "depart_after": .object(["type": .string("string"), "description": .string("出發時間錨點 HH:mm（Asia/Taipei），預設現在")])
                    ]),
                    "required": .array([.string("from_stop"), .string("to"), .string("city")]),
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
            case "bus_rail_route":
                return try await executeBusRailRoute(arguments: arguments, client: client, cache: cache)
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

        // Compose — Stage 3c-ii.2: route through the RaptorCore strategy ensemble
        // (ComposedStrategy floor + RaptorStrategy). For transit_route's ≤1-transfer
        // journeys the proven floor dominates, so the output is identical to before.
        let inputs = RaptorCore.RoutingInputs(traConnections: traConnections, metro: metroData, queryDate: Date())
        guard let journey = RaptorCore.plan(from: from, to: to, departAfterMin: departAfterMin,
                                            inputs: inputs, strategies: [ComposedStrategy(), RaptorStrategy()]) else {
            return emptyRoutes(from: from, to: to, departAfter: departAfter,
                               note: "\(departAfter) 之後查無可達路徑（可能起迄站不在 TRA↔台北捷運的可達範圍，或跨系統無策劃交會站銜接）")
        }
        let it = MultimodalRouter.Itinerary(legs: journey.legs, transfers: journey.transfers, arrMin: journey.arrivalMin)
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
        if let amb = disambiguation(query: fromQ, role: "from", matches: fromMatches, departAfter: departAfter) { return amb }
        let from = fromMatches[0]
        let transferRaw = arguments["transfer"]?.stringValue

        // Bus stops + resolve to_stop (name or StopUID; ambiguous → matches).
        let busStops = BusTools.decodeList(BusStop.self, data: try await client.fetch(
            path: TDXEndpoints.busStop(city.rawValue), cacheTTL: 86400, cache: cache))
        let to: (uid: String, name: String)
        switch resolveBusStop(toQ, stops: busStops, city: city, departAfter: departAfter) {
        case .one(let u, let n): to = (u, n)
        case .result(let r): return r
        }

        // Explicit transfer (3b-i) vs auto-hub (3b-ii).
        if let transferQ = transferRaw, !transferQ.isEmpty {
            let transferMatches = resolveCandidates(transferQ, traStations: traStations, metroStations: metroStations)
            if let amb = disambiguation(query: transferQ, role: "transfer", matches: transferMatches, departAfter: departAfter) { return amb }
            return try await routeExplicit(from: from, transfer: transferMatches[0], to: to, busStops: busStops,
                                           metroSOR: metroSOR, city: city, departAfter: departAfter,
                                           departAfterMin: departAfterMin, nowMin: nowMin, weekday: weekday,
                                           client: client, cache: cache)
        }
        return try await routeAuto(from: from, to: to, busStops: busStops, metroSOR: metroSOR,
                                   traStations: traStations, metroStations: metroStations, city: city,
                                   departAfter: departAfter, departAfterMin: departAfterMin, nowMin: nowMin,
                                   weekday: weekday, client: client, cache: cache)
    }

    // MARK: - rail_bus_route: explicit transfer (3b-i)

    /// The frozen Stage 3b-i path: rail to the given `transfer`, then a name-matched bus leg
    /// to `to`. Unchanged behavior — relocated verbatim from the executor so the auto path
    /// can sit beside it. Fetch order (rail datasets → busStopOfRoute → busSchedule) preserved.
    private static func routeExplicit(from: MultimodalRouter.Stop, transfer: MultimodalRouter.Stop,
                                      to: (uid: String, name: String), busStops: [BusStop],
                                      metroSOR: [MetroStationOfRoute], city: BusCity, departAfter: String,
                                      departAfterMin: Int, nowMin: Int, weekday: Int,
                                      client: TDXClient, cache: Cache) async throws -> CallTool.Result {
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
        let candidates = busCandidates(routes: routes, candidateUIDs: candidateUIDs, to: to)
        if candidates.isEmpty {
            return railBusEmpty(from: from.name, transfer: transfer.name, toName: to.name, city: city, departAfter: departAfter,
                                note: "於 \(transfer.name) 的公車上車站查無直達 \(to.name) 的路線；多段公車轉乘尚未支援（3b-ii）")
        }

        // Bus leg: A2 DISABLED (a now-snapshot cannot time a future post-transfer board);
        // board from schedule/headway only, anchored at rail arrival + walk.
        let scheduleBySig = try await fetchScheduleBySig(city: city, client: client, cache: cache)
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

    // MARK: - rail_bus_route: auto transfer-hub (3b-ii)

    /// Auto-hub path: discover transfer hubs via `to_stop`-anchored reverse search, run the
    /// rail+bus stitch per candidate hub, and return the earliest-arrival itinerary with
    /// `auto_selected_transfer`. Candidate set is bounded; cap overflow is disclosed in a note.
    private static func routeAuto(from: MultimodalRouter.Stop, to: (uid: String, name: String),
                                  busStops: [BusStop], metroSOR: [MetroStationOfRoute],
                                  traStations: [RailStation], metroStations: [(id: String, name: String)],
                                  city: BusCity, departAfter: String, departAfterMin: Int, nowMin: Int,
                                  weekday: Int, client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        // Rail station (id,name) list + id→Stop map (TRA singletons + grouped TRTC platforms).
        var railStations: [(id: String, name: String)] = []
        var stopByID: [String: MultimodalRouter.Stop] = [:]
        for s in traStations {
            let nm = s.stationName.zhTw ?? s.stationID
            railStations.append((s.stationID, nm))
            stopByID[s.stationID] = .init(mode: .tra, ids: [s.stationID], name: nm)
        }
        var metroByName: [String: (name: String, ids: [String])] = [:]
        var metroOrder: [String] = []
        for m in metroStations {
            if metroByName[m.name] == nil { metroByName[m.name] = (m.name, []); metroOrder.append(m.name) }
            metroByName[m.name]!.ids.append(m.id)
        }
        for nm in metroOrder {
            let g = metroByName[nm]!
            guard let rep = g.ids.first else { continue }
            railStations.append((rep, g.name))
            stopByID[rep] = .init(mode: .metro, ids: g.ids, name: g.name)
        }

        // Reverse search: candidate hubs from to_stop's serving routes.
        let routes = BusTools.decodeList(BusStopOfRoute.self, data: try await client.fetch(
            path: TDXEndpoints.busStopOfRoute(city.rawValue), cacheTTL: 3600, cache: cache))
        let discovery = RailBusRouter.candidateHubs(toStopUID: to.uid, routes: routes, railStations: railStations)
        if discovery.hubs.isEmpty {
            return railBusEmpty(from: from.name, transfer: "(自動)", toName: to.name, city: city, departAfter: departAfter,
                                note: "自動選轉乘站：serving \(to.name) 的公車路線上游查無對應鐵路站（站名比對 捷運X站／X車站）；無 rail→bus 交會點")
        }

        // Unique hub stations, closest-upstream first.
        var seenHub = Set<String>()
        var hubStops: [MultimodalRouter.Stop] = []
        for h in discovery.hubs where !seenHub.contains(h.railStationID) {
            seenHub.insert(h.railStationID)
            if let st = stopByID[h.railStationID] { hubStops.append(st) }
        }

        // Bus schedule once; stitch each hub (rail leg + name-matched bus leg), keep the successes.
        let scheduleBySig = try await fetchScheduleBySig(city: city, client: client, cache: cache)
        let transferWalkMin = RailBusRouter.defaultTransferWalkMin
        var results: [RailBusRouter.Result] = []
        for hub in hubStops {
            let railIt: MultimodalRouter.Itinerary
            switch try await composeRailLeg(from: from, to: hub, departAfterMin: departAfterMin,
                                            metroSOR: metroSOR, client: client, cache: cache) {
            case .ok(let it): railIt = it
            case .empty: continue   // hub not rail-reachable from `from`; try the next
            }
            let candidateUIDs = Set(busStops.filter {
                RailBusRouter.busStopMatchesStation(stopName: $0.stopName.zhTw ?? "", stationName: hub.name) }.map { $0.stopUID })
            let candidates = busCandidates(routes: routes, candidateUIDs: candidateUIDs, to: to)
            if candidates.isEmpty { continue }
            let options = BusRouter.route(candidates: candidates, a2BySig: [:], scheduleBySig: scheduleBySig,
                                          nowMin: nowMin, departAfterMin: railIt.arrMin + transferWalkMin, weekday: weekday)
            if let res = RailBusRouter.compose(railLegs: railIt.legs, transferStationName: hub.name,
                                               transferWalkMin: transferWalkMin, busOptions: options, nowMin: nowMin) {
                results.append(res)
            }
        }
        guard let best = RailBusRouter.selectEarliest(results) else {
            return railBusEmpty(from: from.name, transfer: "(自動)", toName: to.name, city: city, departAfter: departAfter,
                                note: "自動選轉乘站：找到 \(hubStops.count) 個候選交會站，但無一可由 \(from.name) 鐵路抵達並直達 \(to.name)")
        }
        let bestHub = hubStops.first { $0.name == best.transferStationName }
            ?? MultimodalRouter.Stop(mode: .tra, ids: [], name: best.transferStationName)
        var payload = railBusPayload(fromName: from.name, transfer: bestHub, toName: to.name,
                                     city: city, departAfter: departAfter, result: best)
        payload["auto_selected_transfer"] = best.transferStationName
        if discovery.droppedCount > 0 {
            payload["auto_hub_note"] = "自動選轉乘站：候選交會站超過上限 \(RailBusRouter.maxAutoHubCandidates)，已取最接近 \(to.name) 的前 \(RailBusRouter.maxAutoHubCandidates) 個，捨棄 \(discovery.droppedCount) 個"
        }
        return ToolResult.json(payload)
    }

    /// Direct-bus candidates: a name-matched boarding stop (`candidateUIDs`) appearing before
    /// `to` in the same route direction. Shared by the explicit and auto paths.
    private static func busCandidates(routes: [BusStopOfRoute], candidateUIDs: Set<String>,
                                      to: (uid: String, name: String)) -> [BusRouter.Candidate] {
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
        return candidates
    }

    /// Bus/Schedule fetch → route+direction → schedule map (graceful; empty when unavailable).
    private static func fetchScheduleBySig(city: BusCity, client: TDXClient, cache: Cache) async throws -> [String: BusSchedule] {
        var scheduleBySig: [String: BusSchedule] = [:]
        if let sc = try? await client.fetch(path: TDXEndpoints.busSchedule(city.rawValue), cacheTTL: 3600, cache: cache) {
            for s in BusTools.decodeList(BusSchedule.self, data: sc) {
                let k = BusRouter.sig(s.routeUID, s.direction ?? 0)
                if scheduleBySig[k] == nil { scheduleBySig[k] = s }
            }
        }
        return scheduleBySig
    }

    // MARK: - bus_rail_route: bus → rail (3c-i)

    /// `bus_rail_route` — bus leg 1 (A2 live) from `from_stop` to a name-matched alight-hub,
    /// then a rail leg 2 via the `transit_route` engine from the hub to `to`. `transfer`
    /// optional (explicit hub vs auto forward-search). Multi-transfer / RAPTOR are out of scope.
    static func executeBusRailRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let fromQ = arguments["from_stop"]?.stringValue, !fromQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from_stop")
        }
        guard let toQ = arguments["to"]?.stringValue, !toQ.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to")
        }
        let city = try BusTools.parseCity(arguments)
        let nowMin = nowMinutesTaipei()
        let weekday = railBusWeekdayTaipei()
        let departAfterMin = arguments["depart_after"]?.stringValue.flatMap(TimetableRouter.minutesOfDay) ?? nowMin
        let departAfter = TimetableRouter.clock(departAfterMin)
        let transferRaw = arguments["transfer"]?.stringValue

        // Rail station data for `to` resolution + hub Stop mapping.
        let traStations: [RailStation] = TDXDecode.list(
            RailStation.self, from: try await client.fetch(path: TDXEndpoints.railStation(.TRA), cacheTTL: 86400, cache: cache))
        let metroSOR: [MetroStationOfRoute] = (try? JSONDecoder().decode(
            [MetroStationOfRoute].self, from: try await client.fetch(path: TDXEndpoints.metroStationOfRoute(.TRTC), cacheTTL: 86400, cache: cache))) ?? []
        let metroStations = uniqueMetroStations(metroSOR)

        // Resolve `to` (rail). Ambiguous → matches.
        let toMatches = resolveCandidates(toQ, traStations: traStations, metroStations: metroStations)
        if let amb = disambiguation(query: toQ, role: "to", matches: toMatches, departAfter: departAfter) { return amb }
        let toStop = toMatches[0]

        // Resolve from_stop (bus). Ambiguous → matches.
        let busStops = BusTools.decodeList(BusStop.self, data: try await client.fetch(
            path: TDXEndpoints.busStop(city.rawValue), cacheTTL: 86400, cache: cache))
        let from: (uid: String, name: String)
        switch resolveBusStop(fromQ, role: "from_stop", stops: busStops, city: city, departAfter: departAfter) {
        case .one(let u, let n): from = (u, n)
        case .result(let r): return r
        }

        // Bus datasets: StopOfRoute, A2 @ from_stop (live board valid — boarding at start), schedule.
        let routes = BusTools.decodeList(BusStopOfRoute.self, data: try await client.fetch(
            path: TDXEndpoints.busStopOfRoute(city.rawValue), cacheTTL: 3600, cache: cache))
        let a2BySig = await fetchA2BySig(city: city, stopUID: from.uid, client: client, cache: cache)
        let scheduleBySig = try await fetchScheduleBySig(city: city, client: client, cache: cache)

        // Rail station (id,name) list + id→Stop map (TRA singletons + grouped TRTC platforms).
        var railStations: [(id: String, name: String)] = []
        var stopByID: [String: MultimodalRouter.Stop] = [:]
        for s in traStations {
            let nm = s.stationName.zhTw ?? s.stationID
            railStations.append((s.stationID, nm))
            stopByID[s.stationID] = .init(mode: .tra, ids: [s.stationID], name: nm)
        }
        var metroByName: [String: (name: String, ids: [String])] = [:]
        var metroOrder: [String] = []
        for m in metroStations {
            if metroByName[m.name] == nil { metroByName[m.name] = (m.name, []); metroOrder.append(m.name) }
            metroByName[m.name]!.ids.append(m.id)
        }
        for nm in metroOrder {
            let g = metroByName[nm]!
            guard let rep = g.ids.first else { continue }
            railStations.append((rep, g.name))
            stopByID[rep] = .init(mode: .metro, ids: g.ids, name: g.name)
        }

        // Candidate alight-hubs: explicit transfer → that station only; auto → forward search.
        let discovery: BusRailRouter.AlightDiscovery
        let isAuto: Bool
        if let tq = transferRaw, !tq.isEmpty {
            let tMatches = resolveCandidates(tq, traStations: traStations, metroStations: metroStations)
            if let amb = disambiguation(query: tq, role: "transfer", matches: tMatches, departAfter: departAfter) { return amb }
            discovery = BusRailRouter.candidateAlightHubs(fromStopUID: from.uid, routes: routes,
                                                          railStations: [(tMatches[0].primaryID, tMatches[0].name)])
            isAuto = false
        } else {
            discovery = BusRailRouter.candidateAlightHubs(fromStopUID: from.uid, routes: routes, railStations: railStations)
            isAuto = true
        }
        if discovery.hubs.isEmpty {
            return busRailEmpty(from: from.name, toName: toStop.name, city: city, departAfter: departAfter,
                                note: isAuto ? "自動選下車站：serving \(from.name) 的公車路線下游查無對應鐵路站（站名比對 捷運X站／X車站）"
                                             : "於指定 transfer 站查無 \(from.name) 下游的對應公車下車站")
        }

        // Unique hub stations, closest-downstream first.
        var seenHub = Set<String>()
        var hubStops: [MultimodalRouter.Stop] = []
        for h in discovery.hubs where !seenHub.contains(h.railStationID) {
            seenHub.insert(h.railStationID)
            if let st = stopByID[h.railStationID] { hubStops.append(st) }
        }

        let transferWalkMin = RailBusRouter.defaultTransferWalkMin
        var results: [BusRailRouter.Result] = []
        for hub in hubStops {
            // Bus leg: from_stop → an alight stop at this hub (downstream), A2 enabled.
            let alightUIDs = Set(busStops.filter {
                RailBusRouter.busStopMatchesStation(stopName: $0.stopName.zhTw ?? "", stationName: hub.name) }.map { $0.stopUID })
            var candidates: [BusRouter.Candidate] = []
            for r in routes {
                guard let oi = r.stops.firstIndex(where: { $0.stopUID == from.uid }) else { continue }
                guard let di = r.stops.indices.first(where: { alightUIDs.contains(r.stops[$0].stopUID) && $0 > oi }) else { continue }
                candidates.append(.init(
                    routeUID: r.routeUID, routeName: r.routeName.zhTw ?? r.routeUID, subRouteName: nil,
                    direction: r.direction ?? 0,
                    originStopUID: from.uid, originStopName: r.stops[oi].stopName.zhTw ?? from.name,
                    destStopUID: r.stops[di].stopUID, destStopName: r.stops[di].stopName.zhTw ?? hub.name))
            }
            if candidates.isEmpty { continue }
            let busOptions = BusRouter.route(candidates: candidates, a2BySig: a2BySig, scheduleBySig: scheduleBySig,
                                             nowMin: nowMin, departAfterMin: departAfterMin, weekday: weekday)
            guard let bestBus = busOptions.first else { continue }   // BusRouter sorts earliest-arrival first
            let busBoardClock = nowMin + (bestBus.boardInMin ?? 0)
            let railDepartAfter = (bestBus.arrivalClockMin ?? busBoardClock) + transferWalkMin
            switch try await composeRailLeg(from: hub, to: toStop, departAfterMin: railDepartAfter,
                                            metroSOR: metroSOR, client: client, cache: cache) {
            case .ok(let railIt):
                results.append(BusRailRouter.compose(busOption: bestBus, busBoardClockMin: busBoardClock,
                                                     hubStationName: hub.name, transferWalkMin: transferWalkMin,
                                                     railLegs: railIt.legs, railArrMin: railIt.arrMin))
            case .empty: continue   // rail unreachable from this hub; try the next
            }
        }
        guard let best = BusRailRouter.selectEarliest(results) else {
            return busRailEmpty(from: from.name, toName: toStop.name, city: city, departAfter: departAfter,
                                note: "找到 \(hubStops.count) 個候選下車站，但無一可由公車直達且鐵路抵達 \(toStop.name)")
        }
        var payload = busRailPayload(fromName: from.name, toStop: toStop, city: city, departAfter: departAfter, result: best)
        if isAuto { payload["auto_selected_transfer"] = best.hubStationName }
        if best.busOption.arrivalClockMin == nil {
            payload["approx_note"] = "公車段為班距期望班次（frequency），抵達時刻從缺；rail 段接續時間以上車時刻 + 步行估算，為近似值"
        }
        if isAuto && discovery.droppedCount > 0 {
            payload["auto_hub_note"] = "自動選下車站：候選超過上限 \(RailBusRouter.maxAutoHubCandidates)，已取最接近 \(from.name) 的前 \(RailBusRouter.maxAutoHubCandidates) 個，捨棄 \(discovery.droppedCount) 個"
        }
        return ToolResult.json(payload)
    }

    /// A2 live ETA at a stop → route+direction → ETA seconds (graceful; empty when absent).
    private static func fetchA2BySig(city: BusCity, stopUID: String, client: TDXClient, cache: Cache) async -> [String: Int] {
        var a2BySig: [String: Int] = [:]
        if let a2 = try? await client.fetch(
            path: TDXEndpoints.busEstimatedTimeOfArrival(city.rawValue),
            queryItems: [URLQueryItem(name: "$filter", value: "StopUID eq '\(stopUID)'")],
            cacheTTL: 0, cache: cache) {
            for a in BusTools.decodeList(BusArrival.self, data: a2) {
                guard let ru = a.routeUID, let eta = a.estimateTime, eta >= 0, (a.stopStatus ?? 0) == 0 else { continue }
                a2BySig[BusRouter.sig(ru, a.direction ?? 0)] = eta
            }
        }
        return a2BySig
    }

    private static func busRailEmpty(from: String, toName: String, city: BusCity,
                                     departAfter: String, note: String) -> CallTool.Result {
        ToolResult.json([
            "from": from, "to": toName, "city": city.rawValue, "depart_after": departAfter,
            "routes": [[String: Any]](), "note": note])
    }

    private static func busRailPayload(fromName: String, toStop: MultimodalRouter.Stop, city: BusCity,
                                       departAfter: String, result: BusRailRouter.Result) -> [String: Any] {
        let bus = result.busOption
        var busLeg: [String: Any] = [
            "mode": "Bus", "line": bus.routeName, "direction": bus.direction,
            "from_name": bus.boardStop, "to_name": bus.alightStop,
            "dep_time": TimetableRouter.clock(result.busBoardClockMin), "source": bus.boardSource]
        if let sub = bus.subRouteName { busLeg["sub_route_name"] = sub }
        if let at = bus.arrivalTime {
            busLeg["arr_time"] = at; busLeg["arrival_source"] = bus.arrivalSource ?? "scheduled"
        } else {
            busLeg["arr_time"] = NSNull()
        }
        if let n = bus.note { busLeg["note"] = n }
        var legs: [[String: Any]] = [busLeg]
        for leg in result.railLegs {
            var d: [String: Any] = [
                "mode": leg.mode.rawValue, "line": leg.line,
                "from_station_id": leg.fromStation, "from_name": leg.fromName,
                "to_station_id": leg.toStation, "to_name": leg.toName,
                "dep_time": TimetableRouter.clock(leg.depMin),
                "arr_time": TimetableRouter.clock(leg.arrMin),
                "source": leg.source]
            if let dm = leg.delayMin { d["delay_min"] = dm }
            legs.append(d)
        }
        let transfers: [[String: Any]] = [[
            "at": result.railLegs.first?.fromStation ?? "", "at_name": result.hubStationName,
            "walk_min": result.transferWalkMin,
            "note": "步行分鐘為估計值（下車站位於 \(result.hubStationName) 站）"]]
        return [
            "from": fromName, "to": toStop.name, "city": city.rawValue, "depart_after": departAfter,
            "transfer_count": 1,
            "arrival_time": TimetableRouter.clock(result.arrivalClockMin),
            "duration_min": max(0, result.arrivalClockMin - result.busBoardClockMin),
            "legs": legs, "transfers": transfers]
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
        // Stage 3c-ii.3: route the rail leg through the RaptorCore ensemble (covers both
        // rail_bus_route and bus_rail_route via this shared helper). ComposedStrategy
        // dominates for these ≤1-transfer rail legs, so the result is identical.
        let inputs = RaptorCore.RoutingInputs(traConnections: traConnections, metro: metroData, queryDate: Date())
        guard let journey = RaptorCore.plan(from: from, to: to, departAfterMin: departAfterMin,
                                            inputs: inputs, strategies: [ComposedStrategy(), RaptorStrategy()]) else {
            return .empty("查無可達路徑（起站與轉乘站可能不在 TRA↔台北捷運可達範圍，或跨系統無策劃交會站銜接）")
        }
        return .ok(MultimodalRouter.Itinerary(legs: journey.legs, transfers: journey.transfers, arrMin: journey.arrivalMin))
    }

    private enum BusStopPick { case one(uid: String, name: String); case result(CallTool.Result) }

    /// to_stop resolution for rail_bus_route: exact StopUID, else fuzzy by name (reusing
    /// `BusTools.fuzzyMatchStops`). One physical stop → `.one`; none/multiple → a ready
    /// result (note / matches).
    private static func resolveBusStop(_ q: String, role: String = "to_stop", stops: [BusStop],
                                       city: BusCity, departAfter: String) -> BusStopPick {
        if let s = stops.first(where: { $0.stopUID == q }) {
            return .one(uid: s.stopUID, name: s.stopName.zhTw ?? s.stopUID)
        }
        let matched = BusTools.fuzzyMatchStops(query: q, in: stops)
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
