// Sources/CheTransportMCP/Tools/RailBusRouter.swift
import Foundation

/// Stage 3b (first slice): rail→bus composition at an explicit, name-matched
/// transfer station. Pure logic — the caller (`TransitTools.executeRailBusRoute`)
/// drives `MultimodalRouter` (rail leg) + `BusRouter` (bus leg) and feeds the
/// results here for name-matching + earliest-arrival stitch. No new engine.
enum RailBusRouter {

    /// Walk minutes from the rail platform to the name-matched bus stop at the same
    /// station. A constant estimate (the matched stop is at the station), not measured.
    static let defaultTransferWalkMin = 5

    /// Stage 3b-ii: max transfer-hub candidates explored when `transfer` is auto-selected.
    /// Each candidate costs a rail-leg route; this bounds the worst-case fan-out while
    /// covering realistic transfer choices. Overflow is disclosed, never silently dropped.
    static let maxAutoHubCandidates = 8

    /// A discovered transfer hub (Stage 3b-ii): a rail station with a name-matched bus
    /// stop on a route that reaches `to_stop` downstream.
    struct HubCandidate: Equatable {
        let railStationName: String
        let railStationID: String
        let boardingStopUID: String
        let boardingStopName: String
        let routeUID: String
        let direction: Int
    }

    /// Result of the reverse search: capped candidates (closest-upstream first) + how
    /// many were dropped by the cap (for honest disclosure).
    struct HubDiscovery: Equatable {
        let hubs: [HubCandidate]
        let droppedCount: Int
    }

    /// `to_stop`-anchored reverse search (Stage 3b-ii). Among `routes`, for each route
    /// where `toStopUID` appears, scan the stops UPSTREAM of it (lower array index =
    /// earlier in the same direction) and name-match each against `railStations`. Each
    /// match is a `(rail hub, boarding stop)` candidate. Candidates are deduplicated by
    /// `(railStationID, boardingStopUID)` keeping the closest-upstream occurrence, ordered
    /// by ascending index gap to `toStopUID` (closest = shortest remaining bus ride), then
    /// capped at `cap` with the dropped count reported. Pure over already-fetched data.
    static func candidateHubs(toStopUID: String, routes: [BusStopOfRoute],
                              railStations: [(id: String, name: String)],
                              cap: Int = maxAutoHubCandidates) -> HubDiscovery {
        // (candidate, index-gap) — gap = toStopIndex - boardingIndex on that route.
        var found: [(cand: HubCandidate, gap: Int)] = []
        for r in routes {
            guard let di = r.stops.firstIndex(where: { $0.stopUID == toStopUID }) else { continue }
            for oi in 0..<di {
                let stop = r.stops[oi]
                let stopName = stop.stopName.zhTw ?? ""
                for station in railStations where busStopMatchesStation(stopName: stopName, stationName: station.name) {
                    found.append((HubCandidate(
                        railStationName: station.name, railStationID: station.id,
                        boardingStopUID: stop.stopUID, boardingStopName: stopName,
                        routeUID: r.routeUID, direction: r.direction ?? 0), di - oi))
                }
            }
        }
        // Dedup by (railStationID, boardingStopUID), keep the smallest gap (closest upstream).
        var bestByKey: [String: (cand: HubCandidate, gap: Int)] = [:]
        for f in found {
            let key = "\(f.cand.railStationID)|\(f.cand.boardingStopUID)"
            if let prev = bestByKey[key], prev.gap <= f.gap { continue }
            bestByKey[key] = f
        }
        // Closest-upstream first; stable tiebreak on station then stop for determinism.
        let ordered = bestByKey.values.sorted {
            $0.gap != $1.gap ? $0.gap < $1.gap
                : ($0.cand.railStationID != $1.cand.railStationID
                    ? $0.cand.railStationID < $1.cand.railStationID
                    : $0.cand.boardingStopUID < $1.cand.boardingStopUID)
        }
        let kept = Array(ordered.prefix(max(0, cap))).map { $0.cand }
        return HubDiscovery(hubs: kept, droppedCount: max(0, ordered.count - kept.count))
    }

    /// Pick the stitched itinerary with the earliest final arrival across candidate hubs
    /// (known arrivals before unknown, then soonest absolute board). Mirrors the per-option
    /// ordering in `compose`, lifted to span hubs. nil when `results` is empty.
    static func selectEarliest(_ results: [Result]) -> Result? {
        results.min { a, b in
            switch (a.arrivalClockMin, b.arrivalClockMin) {
            case let (x?, y?): return x != y ? x < y : a.busBoardClockMin < b.busBoardClockMin
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.busBoardClockMin < b.busBoardClockMin
            }
        }
    }

    /// Whether a bus stop sits at a rail station, by NAME (not geo). Normalizes
    /// `臺`→`台`, then matches structured patterns so district-named stops don't
    /// over-match: a station `南港` accepts `南港行政中心(南港車站)` but rejects
    /// `南港高工`. When the station name already ends in `站` (e.g. metro `台北車站`),
    /// a bare containment is used since `X車站` would double the suffix.
    static func busStopMatchesStation(stopName: String, stationName: String) -> Bool {
        let s = norm(stopName)
        let x = norm(stationName)
        guard !x.isEmpty else { return false }
        if x.hasSuffix("站") { return s.contains(x) }
        return s.contains("捷運\(x)站") || s.contains("\(x)車站") || s.contains("\(x)火車站")
    }

    private static func norm(_ s: String) -> String { s.replacingOccurrences(of: "臺", with: "台") }

    /// The stitched rail→walk→bus itinerary.
    struct Result {
        let railLegs: [MultimodalRouter.Leg]
        let transferStationName: String
        let transferWalkMin: Int
        let bus: BusRouter.Option
        let busBoardClockMin: Int      // absolute board time = nowMin + bus.boardInMin
        let arrivalClockMin: Int?      // final arrival (nil for frequency-only bus leg)
    }

    /// Pick the bus option giving the earliest final arrival (known arrivals before
    /// unknown), then soonest board, and stitch it onto the rail itinerary. The bus
    /// options must already have been computed with `departAfterMin = railArrival +
    /// transferWalkMin` (board is at/after the rail arrival). Returns nil when no
    /// qualifying bus option exists.
    static func compose(railLegs: [MultimodalRouter.Leg], transferStationName: String,
                        transferWalkMin: Int, busOptions: [BusRouter.Option], nowMin: Int) -> Result? {
        guard let best = busOptions.min(by: earlier) else { return nil }
        let boardClock = nowMin + (best.boardInMin ?? 0)
        return Result(railLegs: railLegs, transferStationName: transferStationName,
                      transferWalkMin: transferWalkMin, bus: best,
                      busBoardClockMin: boardClock, arrivalClockMin: best.arrivalClockMin)
    }

    /// Earliest arrival first (known before unknown), then soonest board.
    private static func earlier(_ a: BusRouter.Option, _ b: BusRouter.Option) -> Bool {
        switch (a.arrivalClockMin, b.arrivalClockMin) {
        case let (x?, y?): return x != y ? x < y : (a.boardInMin ?? .max) < (b.boardInMin ?? .max)
        case (_?, nil):    return true
        case (nil, _?):    return false
        case (nil, nil):   return (a.boardInMin ?? .max) < (b.boardInMin ?? .max)
        }
    }
}
