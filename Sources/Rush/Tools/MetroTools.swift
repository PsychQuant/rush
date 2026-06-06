// Sources/Rush/Tools/MetroTools.swift
import Foundation
import MCP

/// `metro_find_route` — O/D routing within one metro system, covering both direct
/// (single-line) and transfer (cross-line) journeys. Metros run on headways, not
/// fixed timetables, so the answer is *which lines to ride, where to change, how
/// long it takes, and how often trains run* — not "the 14:32 train".
///
/// The network is modelled as a graph (see `MetroGraph`) and the shortest path is
/// returned; a direct route is simply a zero-transfer path. Cross-modal transfers
/// (bus / rail) and live train matching are out of scope.
enum MetroTools {

    /// Metro / light-rail operator codes (the RailSystem cases that aren't TRA/THSR).
    static let metroSystems: [RailSystem] = [.TRTC, .TYMC, .KRTC, .TMRT, .NTDLRT, .KLRT]

    /// Sentinel for headway when the system serves no frequency data for a line.
    static let missingValue = -1

    // MARK: - Tool definition

    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "metro_find_route",
                description: "查捷運 O/D 路線（含跨線轉乘）：給起站、迄站、捷運系統，建站網圖跑最短路徑，回傳一或多條候選路徑。每條路徑含 legs（每段搭乘一條線：線名/顏色 + 該段旅行時間 + 班距）、transfers（每個換乘站：步行時間 walk_min + 估計等車 wait_min）、transfer_count、總 travel_time_min。直達 = 1 leg / 0 transfer。捷運按班距營運，故不回傳「某班車幾點」。兩站不連通回空 routes + note。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object([
                            "type": .string("string"),
                            "description": .string("起站 ID（用 rail_search_stations 查詢，例：板南線台北車站 BL12）")
                        ]),
                        "to": .object([
                            "type": .string("string"),
                            "description": .string("迄站 ID（用 rail_search_stations 查詢，例：淡水信義線淡水 R28）")
                        ]),
                        "system": .object([
                            "type": .string("string"),
                            "description": .string("捷運系統代碼（TRTC 台北、TYMC 桃園、KRTC 高雄、TMRT 台中、NTDLRT 新北、KLRT 高雄輕軌）"),
                            "enum": .array([
                                .string("TRTC"), .string("TYMC"), .string("KRTC"),
                                .string("TMRT"), .string("NTDLRT"), .string("KLRT")
                            ])
                        ])
                    ]),
                    "required": .array([.string("from"), .string("to"), .string("system")]),
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
            case "metro_find_route":
                return try await executeFindRoute(arguments: arguments, client: client, cache: cache)
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

    // MARK: - Executor

    private static func executeFindRoute(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let from = arguments["from"]?.stringValue, !from.isEmpty else {
            throw TDXError.decoding("Missing required parameter: from")
        }
        guard let to = arguments["to"]?.stringValue, !to.isEmpty else {
            throw TDXError.decoding("Missing required parameter: to")
        }
        guard let sysCode = arguments["system"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: system")
        }
        guard let sys = RailSystem(rawValue: sysCode) else {
            throw TDXError.decoding("Invalid system '\(sysCode)'. Use rail_list_systems to see valid codes.")
        }
        guard metroSystems.contains(sys) else {
            throw TDXError.decoding("metro_find_route 僅支援捷運系統（TRTC/TYMC/KRTC/TMRT/NTDLRT/KLRT）；台鐵/高鐵請改用 rail_find_trains")
        }

        // Build the graph from the full station network. All five datasets are
        // static (24h cached); the current headway band is selected client-side.
        let sorData = try await client.fetch(path: TDXEndpoints.metroStationOfRoute(sys), cacheTTL: 86400, cache: cache)
        let s2sData = try await client.fetch(path: TDXEndpoints.metroS2STravelTime(sys), cacheTTL: 86400, cache: cache)
        let freqData = try await client.fetch(path: TDXEndpoints.metroFrequency(sys), cacheTTL: 86400, cache: cache)
        let lineData = try await client.fetch(path: TDXEndpoints.metroLine(sys), cacheTTL: 86400, cache: cache)
        // LineTransfer: single-line systems return HTTP 400 (fetch throws) or an
        // empty array — tolerate both as "no transfer edges", not an error.
        var lineTransfer: [MetroLineTransfer] = []
        if let ltData = try? await client.fetch(path: TDXEndpoints.metroLineTransfer(sys), cacheTTL: 86400, cache: cache) {
            lineTransfer = (try? JSONDecoder().decode([MetroLineTransfer].self, from: ltData)) ?? []
        }

        let stationOfRoute = (try? JSONDecoder().decode([MetroStationOfRoute].self, from: sorData)) ?? []
        let s2s = (try? JSONDecoder().decode([MetroS2STravelTime].self, from: s2sData)) ?? []
        let frequency = (try? JSONDecoder().decode([MetroFrequency].self, from: freqData)) ?? []
        let line = (try? JSONDecoder().decode([MetroLine].self, from: lineData)) ?? []

        let headwayRange = headwayByLine(frequency: frequency, now: Date())
        let graph = MetroGraph(
            stationOfRoute: stationOfRoute, s2s: s2s, lineTransfer: lineTransfer,
            headwayByLine: headwayRange.mapValues { $0.0 })
        let lineMeta = Dictionary(line.compactMap { l in l.lineID.map { ($0, l) } }, uniquingKeysWith: { a, _ in a })

        let routes = candidateRoutes(graph: graph, lineMeta: lineMeta, headwayRange: headwayRange, from: from, to: to)
        if routes.isEmpty {
            return ToolResult.json([
                "from": from, "to": to, "system": sys.rawValue, "routes": [],
                "note": "在此捷運系統內找不到連通 \(from) 與 \(to) 的路徑（站 ID 可能有誤，或屬不同系統）。"
            ])
        }
        return ToolResult.json(["from": from, "to": to, "system": sys.rawValue, "routes": routes])
    }
}

// MARK: - Route assembly + candidate selection (pure, testable)

extension MetroTools {

    /// Build the candidate route list: the shortest-by-time path plus the
    /// fewest-transfers path (if different), deduped by station sequence, sorted
    /// by total time, capped at three. Empty when the two stations are not connected.
    static func candidateRoutes(
        graph: MetroGraph, lineMeta: [String: MetroLine], headwayRange: [String: (Int, Int)],
        from: String, to: String
    ) -> [[String: Any]] {
        // Stage 3c-ii.3: dispatch through RaptorCore's metro-routes facade (delegates to
        // the graph's by-time + by-transfers searches; structural, not ensemble capability).
        let paths: [MetroGraph.Path] = RaptorCore.planMetroRoutes(graph: graph, from: from, to: to)

        var seen = Set<String>()
        let unique = paths.filter { seen.insert($0.stations.joined(separator: ">")).inserted }
        let routes = unique.map { assemblePath($0, lineMeta: lineMeta, headwayRange: headwayRange, graph: graph) }
        return Array(routes.sorted {
            ($0["travel_time_min"] as? Int ?? .max) < ($1["travel_time_min"] as? Int ?? .max)
        }.prefix(3))
    }

    /// Turn a graph path into the output route dict: legs (one per line ridden) +
    /// transfers (one per line change) + transfer_count + total travel_time_min.
    static func assemblePath(
        _ path: MetroGraph.Path, lineMeta: [String: MetroLine],
        headwayRange: [String: (Int, Int)], graph: MetroGraph
    ) -> [String: Any] {
        let stations = path.stations
        var legs: [[String: Any]] = []
        var transfers: [[String: Any]] = []
        var legLine: String?
        var legFromIdx: Int?
        var legMinutes = 0.0

        func closeLeg(endIdx: Int) {
            guard let line = legLine, let fi = legFromIdx else { return }
            let (hmn, hmx) = headwayRange[line] ?? (missingValue, missingValue)
            let meta = lineMeta[line]
            legs.append([
                "line_id": line,
                "line_name": meta?.lineName?.zhTw ?? line,
                "line_color": meta?.lineColor ?? "",
                "from_station_id": stations[fi],
                "from_name": graph.stationName(stations[fi]) ?? "",
                "to_station_id": stations[endIdx],
                "to_name": graph.stationName(stations[endIdx]) ?? "",
                "travel_time_min": Int(legMinutes.rounded()),
                "headway_min": hmn,
                "headway_max_min": hmx
            ])
            legLine = nil; legFromIdx = nil; legMinutes = 0
        }

        for (i, edge) in path.edges.enumerated() {
            switch edge.kind {
            case .ride(let line):
                if legLine == nil { legLine = line; legFromIdx = i }
                else if legLine != line { closeLeg(endIdx: i); legLine = line; legFromIdx = i }
                legMinutes += edge.minutes
            case .transfer(let fromLine, let toLine, let walkMin, let waitMin):
                closeLeg(endIdx: i)   // current leg ends at the interchange (from side)
                transfers.append([
                    "station_id": stations[i],
                    "station_name": graph.stationName(stations[i]) ?? graph.stationName(stations[i + 1]) ?? "",
                    "from_line": fromLine,
                    "to_line": toLine,
                    "walk_min": walkMin,
                    "wait_min": waitMin
                ])
            }
        }
        closeLeg(endIdx: stations.count - 1)

        return [
            "transfer_count": path.transferCount,
            "travel_time_min": Int(path.totalMinutes.rounded()),
            "legs": legs,
            "transfers": transfers
        ]
    }
}

// MARK: - Headway band selection (per line, current Asia/Taipei period)

extension MetroTools {

    /// Current-period (min, max) headway for every line that has frequency data.
    /// Used both for the graph's transfer-wait estimate and for per-leg display.
    static func headwayByLine(frequency: [MetroFrequency], now: Date) -> [String: (Int, Int)] {
        var out: [String: (Int, Int)] = [:]
        for lineID in Set(frequency.compactMap { $0.lineID }) {
            let band = currentHeadwayBand(frequency.filter { $0.lineID == lineID }, now: now)
            if band.0 != missingValue { out[lineID] = band }
        }
        return out
    }

    /// Pick the headway band matching the queried weekday + time-of-day from a
    /// line's frequency entries. National-holiday detection is out of scope —
    /// weekday match only.
    static func currentHeadwayBand(_ freqs: [MetroFrequency], now: Date) -> (Int, Int) {
        guard !freqs.isEmpty else { return (missingValue, missingValue) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let weekday = cal.component(.weekday, from: now)
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let f = freqs.first { matchesServiceDay($0.serviceDay, weekday: weekday) } ?? freqs.first
        guard let freq = f, !freq.headways.isEmpty else { return (missingValue, missingValue) }
        let band = freq.headways.first { bandContains($0, minute: nowMin) } ?? freq.headways.first
        guard let b = band else { return (missingValue, missingValue) }
        return (b.minHeadwayMins, b.maxHeadwayMins)
    }

    static func matchesServiceDay(_ sd: MetroServiceDay, weekday: Int) -> Bool {
        switch weekday {
        case 1: return sd.sunday
        case 2: return sd.monday
        case 3: return sd.tuesday
        case 4: return sd.wednesday
        case 5: return sd.thursday
        case 6: return sd.friday
        case 7: return sd.saturday
        default: return false
        }
    }

    private static func bandContains(_ h: MetroHeadway, minute: Int) -> Bool {
        guard let start = minutesOfDay(h.startTime) else { return false }
        var end = minutesOfDay(h.endTime) ?? 0
        if end == 0 { end = 1440 }          // "00:00" as an end means midnight (end of day)
        return minute >= start && minute < end
    }

    /// Parse "HH:mm" to minutes-of-day. "24:00" → 1440 (headway end-of-service-day).
    /// Bounds the components (h 0–24, m 0–59) before the multiply: validates the
    /// time AND prevents an integer-overflow trap on malformed data.
    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), (0...24).contains(h),
              let m = Int(parts[1]), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}
