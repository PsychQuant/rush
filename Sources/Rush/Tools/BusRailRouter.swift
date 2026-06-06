// Sources/Rush/Tools/BusRailRouter.swift
import Foundation

/// Stage 3c-i: bus→rail composition — the forward dual of `RailBusRouter`. Pure
/// logic; the caller (`TransitTools.executeBusRailRoute`) drives `BusRouter` (leg 1,
/// A2 live) + `MultimodalRouter` (leg 2, rail) and feeds the results here for the
/// forward alight-hub discovery + bus-then-rail stitch. No new engine.
///
/// The mirror of 3b-ii's reverse search: there the hub is UPSTREAM of `to_stop`;
/// here it is DOWNSTREAM of `from_stop`. Reuses `RailBusRouter.busStopMatchesStation`
/// (the frozen name-match) and `RailBusRouter.maxAutoHubCandidates` (the cap).
enum BusRailRouter {

    /// A discovered alight-hub: a rail station with a name-matched bus stop DOWNSTREAM
    /// of `from_stop` on a serving route (where you get off the bus and onto rail).
    struct AlightHub: Equatable {
        let railStationName: String
        let railStationID: String
        let alightStopUID: String
        let alightStopName: String
        let routeUID: String
        let direction: Int
    }

    /// Capped candidates (closest-downstream first) + how many the cap dropped.
    struct AlightDiscovery: Equatable {
        let hubs: [AlightHub]
        let droppedCount: Int
    }

    /// `from_stop`-anchored forward search. Among `routes`, for each route where
    /// `fromStopUID` appears, scan the stops DOWNSTREAM of it (higher array index =
    /// later in the same direction) and name-match them to `railStations`. Each match
    /// is a `(rail hub, alight stop)` candidate. Deduplicated by `(railStationID,
    /// alightStopUID)` keeping the closest-downstream occurrence, ordered by ascending
    /// index gap to `fromStopUID` (closest = shortest bus ride), then capped with the
    /// dropped count reported. Pure over already-fetched data.
    static func candidateAlightHubs(fromStopUID: String, routes: [BusStopOfRoute],
                                    railStations: [(id: String, name: String)],
                                    cap: Int = RailBusRouter.maxAutoHubCandidates) -> AlightDiscovery {
        var found: [(hub: AlightHub, gap: Int)] = []
        for r in routes {
            guard let fi = r.stops.firstIndex(where: { $0.stopUID == fromStopUID }) else { continue }
            guard fi + 1 < r.stops.count else { continue }
            for ai in (fi + 1)..<r.stops.count {
                let stop = r.stops[ai]
                let stopName = stop.stopName.zhTw ?? ""
                for station in railStations where RailBusRouter.busStopMatchesStation(stopName: stopName, stationName: station.name) {
                    found.append((AlightHub(
                        railStationName: station.name, railStationID: station.id,
                        alightStopUID: stop.stopUID, alightStopName: stopName,
                        routeUID: r.routeUID, direction: r.direction ?? 0), ai - fi))
                }
            }
        }
        // Dedup by (railStationID, alightStopUID), keep the smallest gap (closest downstream).
        var bestByKey: [String: (hub: AlightHub, gap: Int)] = [:]
        for f in found {
            let key = "\(f.hub.railStationID)|\(f.hub.alightStopUID)"
            if let prev = bestByKey[key], prev.gap <= f.gap { continue }
            bestByKey[key] = f
        }
        let ordered = bestByKey.values.sorted {
            $0.gap != $1.gap ? $0.gap < $1.gap
                : ($0.hub.railStationID != $1.hub.railStationID
                    ? $0.hub.railStationID < $1.hub.railStationID
                    : $0.hub.alightStopUID < $1.hub.alightStopUID)
        }
        let kept = Array(ordered.prefix(max(0, cap))).map { $0.hub }
        return AlightDiscovery(hubs: kept, droppedCount: max(0, ordered.count - kept.count))
    }

    /// The stitched bus→walk→rail itinerary (bus leg 1, then rail legs).
    struct Result {
        let busOption: BusRouter.Option
        let busBoardClockMin: Int      // absolute board = nowMin + busOption.boardInMin
        let hubStationName: String
        let transferWalkMin: Int
        let railLegs: [MultimodalRouter.Leg]
        let arrivalClockMin: Int       // final rail arrival
    }

    /// Package a bus leg + rail itinerary into a bus→rail Result. The caller computes
    /// the rail anchor (bus arrival or board + walk) and passes the resulting rail legs
    /// + arrival; this just stitches.
    static func compose(busOption: BusRouter.Option, busBoardClockMin: Int, hubStationName: String,
                        transferWalkMin: Int, railLegs: [MultimodalRouter.Leg], railArrMin: Int) -> Result {
        Result(busOption: busOption, busBoardClockMin: busBoardClockMin, hubStationName: hubStationName,
               transferWalkMin: transferWalkMin, railLegs: railLegs, arrivalClockMin: railArrMin)
    }

    /// Pick the itinerary with the earliest final rail arrival across candidate hubs,
    /// tie-broken by soonest bus board. nil when `results` is empty.
    static func selectEarliest(_ results: [Result]) -> Result? {
        results.min {
            $0.arrivalClockMin != $1.arrivalClockMin
                ? $0.arrivalClockMin < $1.arrivalClockMin
                : $0.busBoardClockMin < $1.busBoardClockMin
        }
    }
}
