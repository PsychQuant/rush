// Sources/Rush/Tools/TimetableRouter.swift
import Foundation

/// Earliest-arrival routing over a TRA timetable (the real per-train departure /
/// arrival times from `DailyTrainTimetable` OD), with live per-train delays
/// applied. This is the Stage 1 substrate of the time-dependent routing engine:
/// the chosen itinerary changes with live conditions (a delayed train can lose
/// to a later on-time one).
///
/// Algorithm: a **connection-scan / label-setting** earliest-arrival pass — sort
/// the ride connections by (live-adjusted) departure and relax a per-station
/// earliest-arrival label. This is CSA's canonical form; it yields the same
/// itinerary as a time-expanded-graph Dijkstra with simpler code.
enum TimetableRouter {

    /// One ride between two consecutive timetabled stops of a single train, with
    /// the train's live delay already folded into the times.
    struct Connection {
        let trainNo: String
        let fromStation: String
        let fromName: String
        let toStation: String
        let toName: String
        let depMin: Int       // minutes-of-day, live-adjusted
        let arrMin: Int       // minutes-of-day, live-adjusted (+1440 if it crosses midnight)
        let delayMin: Int     // delay applied to this train (0 if none / no live data)
        let live: Bool        // a live entry existed for this train
    }

    /// One leg of the itinerary: a maximal run on a single train.
    struct Leg {
        let trainNo: String
        let fromStation: String
        let fromName: String
        let toStation: String
        let toName: String
        let depMin: Int
        let arrMin: Int
        let delayMin: Int
        let live: Bool
    }

    struct Itinerary {
        let legs: [Leg]
        let arrMin: Int       // arrival at destination, minutes-of-day (live-adjusted)
    }

    /// Parse "HH:mm" to minutes-of-day. Returns nil on malformed or out-of-range
    /// input. Bounding the components (h 0–23, m 0–59) before the multiply both
    /// validates the time and prevents an integer-overflow trap on hostile input
    /// (e.g. `depart_after` is a caller-supplied tool argument).
    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), (0..<24).contains(h),
              let m = Int(parts[1]), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Format minutes-of-day back to "HH:mm" (wraps past midnight for next-day arrivals).
    static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Build ride connections from the OD trains, folding each train's live delay
    /// into its stop times. Each consecutive stop pair becomes one connection.
    static func connections(from trains: [RailODFare], delays: [String: Int]) -> [Connection] {
        var out: [Connection] = []
        for train in trains {
            let no = train.trainInfo.trainNo
            let delay = delays[no]                 // nil when no live data for this train
            let shift = delay ?? 0
            let stops = train.stopTimes
            guard stops.count >= 2 else { continue }
            for i in 0..<(stops.count - 1) {
                let a = stops[i], b = stops[i + 1]
                guard let depRaw = a.departureTime.flatMap(minutesOfDay),
                      let arrRaw = b.arrivalTime.flatMap(minutesOfDay) else { continue }
                var dep = depRaw + shift
                var arr = arrRaw + shift
                if arr < dep { arr += 1440 }       // crosses midnight
                out.append(Connection(
                    trainNo: no,
                    fromStation: a.stationID, fromName: a.stationName.zhTw ?? a.stationID,
                    toStation: b.stationID, toName: b.stationName.zhTw ?? b.stationID,
                    depMin: dep, arrMin: arr,
                    delayMin: shift, live: delay != nil))
            }
        }
        return out
    }

    /// Earliest-arrival from `from`, boarding only connections departing at or
    /// after `departAfterMin`. Returns nil when the destination is unreachable.
    static func earliestArrival(connections: [Connection], from: String, to: String, departAfterMin: Int) -> Itinerary? {
        var bestArrival: [String: Int] = [from: departAfterMin]
        var predecessor: [String: Connection] = [:]

        // Relax connections in departure order (connection scan).
        for c in connections.sorted(by: { $0.depMin < $1.depMin }) {
            guard let here = bestArrival[c.fromStation], here <= c.depMin else { continue }
            if c.arrMin < (bestArrival[c.toStation] ?? Int.max) {
                bestArrival[c.toStation] = c.arrMin
                predecessor[c.toStation] = c
            }
        }

        guard let arr = bestArrival[to] else { return nil }

        // Reconstruct the connection chain, then merge consecutive same-train
        // connections into legs.
        var chain: [Connection] = []
        var cur = to
        while let c = predecessor[cur] {
            chain.append(c)
            cur = c.fromStation
            if cur == from { break }
        }
        chain.reverse()
        guard !chain.isEmpty else { return nil }

        var legs: [Leg] = []
        var run = chain[0]
        var runStart = chain[0]
        func flush(_ end: Connection) {
            legs.append(Leg(
                trainNo: runStart.trainNo,
                fromStation: runStart.fromStation, fromName: runStart.fromName,
                toStation: end.toStation, toName: end.toName,
                depMin: runStart.depMin, arrMin: end.arrMin,
                delayMin: runStart.delayMin, live: runStart.live))
        }
        for c in chain.dropFirst() {
            if c.trainNo == run.trainNo { run = c }      // same train → extend leg
            else { flush(run); runStart = c; run = c }   // new train → new leg
        }
        flush(run)

        return Itinerary(legs: legs, arrMin: arr)
    }
}
