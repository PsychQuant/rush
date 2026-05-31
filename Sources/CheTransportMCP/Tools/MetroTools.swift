// Sources/CheTransportMCP/Tools/MetroTools.swift
import Foundation
import MCP

/// `metro_find_route` — direct (single-line) O/D routing for the six metro
/// systems. Metros run on headways, not fixed timetables, so the natural answer
/// to "A → B" is *which line connects them, how long it takes, and how often it
/// runs* — not "the 14:32 train". Transfer routing (crossing lines) is out of
/// scope here and tracked separately (PsychQuant/che-transport-mcp#6).
enum MetroTools {

    /// Metro / light-rail operator codes (the RailSystem cases that aren't TRA/THSR).
    static let metroSystems: [RailSystem] = [.TRTC, .TYMC, .KRTC, .TMRT, .NTDLRT, .KLRT]

    /// Sentinel emitted for travel-time / headway when the system returns no
    /// data for the route (sparse light-rail). Empty data is not an error.
    static let missingValue = -1

    // MARK: - Tool definition

    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "metro_find_route",
                description: "查捷運直達 O/D：給起站、迄站、捷運系統，回傳連接兩站的直達線（線名/顏色）、站到站旅行時間（分）、與當下時段班距（分）。捷運按班距營運，故不回傳「某班車幾點」。無直達線回空 routes + 轉乘提示（轉乘規劃尚未支援）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from": .object([
                            "type": .string("string"),
                            "description": .string("起站 ID（用 rail_search_stations 查詢，例：板南線台北車站）")
                        ]),
                        "to": .object([
                            "type": .string("string"),
                            "description": .string("迄站 ID（用 rail_search_stations 查詢）")
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

        // Gate: StationOfRoute first. If no single route covers both stations in
        // the travel direction, return empty + transfer hint WITHOUT the other
        // three (static) fetches — empty is not an error.
        let sorData = try await client.fetch(path: TDXEndpoints.metroStationOfRoute(sys), cacheTTL: 86400, cache: cache)
        let stationOfRoute = (try? JSONDecoder().decode([MetroStationOfRoute].self, from: sorData)) ?? []

        guard hasDirectRoute(from: from, to: to, in: stationOfRoute) else {
            return resultJSON([
                "from": from, "to": to, "system": sys.rawValue,
                "routes": [],
                "note": "找不到直達路線（兩站不在同一條線上），可能需要轉乘。轉乘路線規劃尚未支援（規劃中：PsychQuant/che-transport-mcp#6）。"
            ])
        }

        // Enrich: travel times, headways, line names. All three are static daily
        // datasets (current headway band is selected client-side from `Date()`),
        // so 24h cache is correct. Sequential so cold-cache ordering is stable.
        let s2sData = try await client.fetch(path: TDXEndpoints.metroS2STravelTime(sys), cacheTTL: 86400, cache: cache)
        let freqData = try await client.fetch(path: TDXEndpoints.metroFrequency(sys), cacheTTL: 86400, cache: cache)
        let lineData = try await client.fetch(path: TDXEndpoints.metroLine(sys), cacheTTL: 86400, cache: cache)

        let s2s = (try? JSONDecoder().decode([MetroS2STravelTime].self, from: s2sData)) ?? []
        let frequency = (try? JSONDecoder().decode([MetroFrequency].self, from: freqData)) ?? []
        let line = (try? JSONDecoder().decode([MetroLine].self, from: lineData)) ?? []

        let routes = assembleDirectRoutes(
            from: from, to: to,
            stationOfRoute: stationOfRoute, s2s: s2s, frequency: frequency, line: line,
            now: Date())

        return resultJSON(["from": from, "to": to, "system": sys.rawValue, "routes": routes])
    }

    private static func resultJSON(_ payload: [String: Any]) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: JSONSanitize.clean(payload))) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}

// MARK: - Pure routing core (testable without a server)

extension MetroTools {

    /// True if any route's station sequence contains both stations with the
    /// origin appearing before the destination (i.e. a direct ride in that
    /// travel direction exists).
    static func hasDirectRoute(from: String, to: String, in routes: [MetroStationOfRoute]) -> Bool {
        routes.contains { route in
            guard let f = index(of: from, in: route), let t = index(of: to, in: route) else { return false }
            return f < t
        }
    }

    /// Build the direct-route result list (one entry per matching route/direction),
    /// sorted by travel time ascending (sentinel/unknown times sort last).
    static func assembleDirectRoutes(
        from: String, to: String,
        stationOfRoute: [MetroStationOfRoute],
        s2s: [MetroS2STravelTime],
        frequency: [MetroFrequency],
        line: [MetroLine],
        now: Date
    ) -> [[String: Any]] {
        var out: [[String: Any]] = []

        for route in stationOfRoute {
            guard let fIdx = index(of: from, in: route),
                  let tIdx = index(of: to, in: route),
                  fIdx < tIdx else { continue }

            let stations = route.stations
            let travelMin = travelTimeMinutes(route: route, fromIdx: fIdx, toIdx: tIdx, s2s: s2s)
            let (hMin, hMax) = headway(routeID: route.routeID, frequency: frequency, now: now)
            let lineMeta = line.first { $0.lineID == route.lineID }

            out.append([
                "line_id": route.lineID ?? "",
                "line_name": lineMeta?.lineName?.zhTw ?? route.lineName?.zhTw ?? (route.lineID ?? ""),
                "line_color": lineMeta?.lineColor ?? "",
                "route_id": route.routeID ?? "",
                "route_name": route.routeName?.zhTw ?? "",
                "direction": route.direction ?? missingValue,
                "travel_time_min": travelMin,
                "headway_min": hMin,
                "headway_max_min": hMax,
                "stations_count": tIdx - fIdx + 1,
                "from_name": stations[fIdx].stationName.zhTw ?? "",
                "to_name": stations[tIdx].stationName.zhTw ?? ""
            ])
        }

        // Ascending travel time; sentinel (-1, unknown) sinks to the bottom.
        return out.sorted { a, b in
            let ta = a["travel_time_min"] as? Int ?? missingValue
            let tb = b["travel_time_min"] as? Int ?? missingValue
            return rank(ta) < rank(tb)
        }
    }

    private static func rank(_ t: Int) -> Int { t < 0 ? Int.max : t }

    private static func index(of stationID: String, in route: MetroStationOfRoute) -> Int? {
        route.stations.firstIndex { $0.stationID == stationID }
    }

    /// Sum segment run-times between two station indices, plus dwell at the
    /// intermediate stations (the destination's dwell is excluded — you don't
    /// wait once you've arrived). Returns minutes, or `missingValue` if the
    /// system provides no matching travel-time data.
    static func travelTimeMinutes(route: MetroStationOfRoute, fromIdx: Int, toIdx: Int, s2s: [MetroS2STravelTime]) -> Int {
        // TDX stores S2S segments in a single direction only (e.g. 板南線 stores the
        // descending BL23→…→BL01 order — the forward BL12→BL13 pair exists in zero
        // elements). Adjacent-station run-time is direction-symmetric, so register
        // both orders and look up either. Station-pair IDs are line-prefixed
        // (e.g. BL12,BL13) → globally unique, so drawing from every element is
        // collision-free even across lines.
        let segments = s2s.flatMap { $0.travelTimes }
        guard !segments.isEmpty else { return missingValue }
        var byPair: [Pair: MetroTravelTime] = [:]
        for seg in segments {
            let fwd = Pair(seg.fromStationID, seg.toStationID)
            let rev = Pair(seg.toStationID, seg.fromStationID)
            if byPair[fwd] == nil { byPair[fwd] = seg }
            if byPair[rev] == nil { byPair[rev] = seg }
        }

        var totalSec = 0
        var matched = 0
        let stations = route.stations
        for i in fromIdx..<toIdx {
            guard let seg = byPair[Pair(stations[i].stationID, stations[i + 1].stationID)] else { continue }
            matched += 1
            totalSec += seg.runTime
            // Dwell counts at every intermediate stop, i.e. not the final segment.
            if i < toIdx - 1 { totalSec += seg.stopTime ?? 0 }
        }
        guard matched > 0 else { return missingValue }
        return Int((Double(totalSec) / 60.0).rounded())
    }

    /// Pick the headway band for the queried weekday + time-of-day. Returns
    /// `(missingValue, missingValue)` when the system has no headway data for the
    /// route. National-holiday detection is out of scope for v1 — weekday match only.
    static func headway(routeID: String?, frequency: [MetroFrequency], now: Date) -> (Int, Int) {
        let forRoute = frequency.filter { $0.routeID == routeID }
        guard !forRoute.isEmpty else { return (missingValue, missingValue) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let weekday = cal.component(.weekday, from: now)              // 1=Sun … 7=Sat
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        let freq = forRoute.first { matchesServiceDay($0.serviceDay, weekday: weekday) } ?? forRoute.first
        guard let f = freq, !f.headways.isEmpty else { return (missingValue, missingValue) }

        // Prefer the band covering the current time; otherwise fall back to the
        // first band (better an approximate headway than nothing — #5 open question).
        let band = f.headways.first { bandContains($0, minute: nowMin) } ?? f.headways.first
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

    /// Parse "HH:mm" to minutes-of-day. "24:00" → 1440 (end of service day).
    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Hashable station-pair key for O(1) segment lookup.
    private struct Pair: Hashable { let a: String; let b: String; init(_ a: String, _ b: String) { self.a = a; self.b = b } }
}
