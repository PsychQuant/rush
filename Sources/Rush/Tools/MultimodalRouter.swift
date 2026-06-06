// Sources/Rush/Tools/MultimodalRouter.swift
import Foundation

/// Stage 2 of the routing engine: TRA ↔ Taipei-Metro multi-modal earliest-arrival,
/// composed from the two existing single-mode routers at a curated interchange.
///
/// **Time-anchored multi-leg composition** (see design):
///   - TRA legs   → `TimetableRouter.earliestArrival` (CSA + live `TrainLiveBoard` delay), `source: live`.
///   - Metro legs → `MetroGraph.shortestPathByTime`, the graph rebuilt with the headway band
///                  active at the moment the traveller enters the metro, `source: frequency`.
///   - The seam   → `InterchangeRegistry` (cross-system station pairing + walk time).
///
/// A journey crosses modes at most once. Same-system journeys delegate to one router.
/// This reuses both routers unchanged — no unified graph, no duplication of
/// `MetroGraph`'s edge model.
enum MultimodalRouter {

    enum Mode: String { case tra = "TRA", metro = "Metro" }

    /// A resolved endpoint. A metro interchange exposes several line-platform node
    /// ids for the same physical station (e.g. 西門 = BL11 + G12); `ids` holds them
    /// all and the router reaches/leaves via whichever gives the earliest arrival.
    /// TRA stations have a single id.
    struct Stop {
        let mode: Mode
        let ids: [String]
        let name: String
        var primaryID: String { ids.first ?? "" }
    }

    struct Leg {
        let mode: Mode
        let line: String        // train number for TRA, line id for Metro
        let fromStation: String
        let fromName: String
        let toStation: String
        let toName: String
        let depMin: Int         // minutes-of-day (TRA live-adjusted; Metro expected)
        let arrMin: Int
        let delayMin: Int?      // TRA only
        let source: String      // "live" | "scheduled" | "frequency"
    }

    struct Transfer {
        let at: String
        let atName: String
        let walkMin: Int
    }

    struct Itinerary {
        let legs: [Leg]
        let transfers: [Transfer]
        let arrMin: Int
        var transferCount: Int { transfers.count }
    }

    /// Raw metro datasets needed to (re)build a `MetroGraph` at a chosen band.
    struct MetroData {
        let stationOfRoute: [MetroStationOfRoute]
        let s2s: [MetroS2STravelTime]
        let lineTransfer: [MetroLineTransfer]
        let frequency: [MetroFrequency]
    }

    // MARK: - Entry point (pure: deterministic given inputs)

    /// Compose the earliest-arrival itinerary. `traConnections` must already contain
    /// the relevant TRA connections (origin↔interchanges and/or interchange↔dest, or
    /// origin↔dest for a TRA-only journey), built via `TimetableRouter.connections`.
    /// `queryDate` anchors weekday/headway-band selection (Asia/Taipei).
    static func route(from: Stop, to: Stop, departAfterMin: Int,
                      traConnections: [TimetableRouter.Connection],
                      metro: MetroData, queryDate: Date) -> Itinerary? {
        switch (from.mode, to.mode) {
        case (.tra, .tra):
            guard let it = TimetableRouter.earliestArrival(
                connections: traConnections, from: from.primaryID, to: to.primaryID, departAfterMin: departAfterMin) else { return nil }
            return Itinerary(legs: it.legs.map(traLeg), transfers: [], arrMin: it.arrMin)

        case (.metro, .metro):
            let graph = metroGraph(at: departAfterMin, queryDate: queryDate, metro: metro)
            let headways = headwayMin(at: departAfterMin, queryDate: queryDate, metro: metro)
            var best: Itinerary?
            for o in from.ids {
                for d in to.ids {
                    guard let part = metroSegment(from: o, to: d, entryMin: departAfterMin, graph: graph, headways: headways) else { continue }
                    let it = Itinerary(legs: part.legs, transfers: part.transfers, arrMin: part.arrMin)
                    if best == nil || it.arrMin < best!.arrMin { best = it }
                }
            }
            return best

        case (.tra, .metro):
            return traToMetro(originTRA: from.primaryID, destMetroNodes: to.ids, departAfterMin: departAfterMin,
                              traConnections: traConnections, metro: metro, queryDate: queryDate)

        case (.metro, .tra):
            return metroToTRA(originMetroNodes: from.ids, destTRA: to.primaryID, departAfterMin: departAfterMin,
                              traConnections: traConnections, metro: metro, queryDate: queryDate)
        }
    }

    // MARK: - Cross-mode compositions

    private static func traToMetro(originTRA: String, destMetroNodes: [String], departAfterMin: Int,
                                   traConnections: [TimetableRouter.Connection],
                                   metro: MetroData, queryDate: Date) -> Itinerary? {
        var best: Itinerary?
        for ix in InterchangeRegistry.entries {
            guard let tra = TimetableRouter.earliestArrival(
                connections: traConnections, from: originTRA, to: ix.traStationID,
                departAfterMin: departAfterMin) else { continue }
            let metroEntryMin = tra.arrMin + ix.walkMin
            let graph = metroGraph(at: metroEntryMin, queryDate: queryDate, metro: metro)
            let headways = headwayMin(at: metroEntryMin, queryDate: queryDate, metro: metro)
            for entryNode in ix.trtcStationIDs {
                for destNode in destMetroNodes {
                    guard let metroPart = metroSegment(from: entryNode, to: destNode,
                                                       entryMin: metroEntryMin, graph: graph, headways: headways) else { continue }
                    let transfer = Transfer(at: ix.traStationID, atName: ix.name, walkMin: ix.walkMin)
                    let legs = tra.legs.map(traLeg) + metroPart.legs
                    let it = Itinerary(legs: legs, transfers: [transfer] + metroPart.transfers, arrMin: metroPart.arrMin)
                    if best == nil || it.arrMin < best!.arrMin { best = it }
                }
            }
        }
        return best
    }

    private static func metroToTRA(originMetroNodes: [String], destTRA: String, departAfterMin: Int,
                                   traConnections: [TimetableRouter.Connection],
                                   metro: MetroData, queryDate: Date) -> Itinerary? {
        let graph = metroGraph(at: departAfterMin, queryDate: queryDate, metro: metro)
        let headways = headwayMin(at: departAfterMin, queryDate: queryDate, metro: metro)
        var best: Itinerary?
        for ix in InterchangeRegistry.entries {
            for exitNode in ix.trtcStationIDs {
                for originNode in originMetroNodes {
                    guard let metroPart = metroSegment(from: originNode, to: exitNode,
                                                       entryMin: departAfterMin, graph: graph, headways: headways) else { continue }
                    let traDepartAfter = metroPart.arrMin + ix.walkMin
                    guard let tra = TimetableRouter.earliestArrival(
                        connections: traConnections, from: ix.traStationID, to: destTRA,
                        departAfterMin: traDepartAfter) else { continue }
                    let transfer = Transfer(at: ix.traStationID, atName: ix.name, walkMin: ix.walkMin)
                    let legs = metroPart.legs + tra.legs.map(traLeg)
                    let it = Itinerary(legs: legs, transfers: metroPart.transfers + [transfer], arrMin: tra.arrMin)
                    if best == nil || it.arrMin < best!.arrMin { best = it }
                }
            }
        }
        return best
    }

    // MARK: - Metro segment → legs + transfers (with clock times)

    private struct MetroSegment {
        let legs: [Leg]
        let transfers: [Transfer]
        let arrMin: Int
    }

    /// Route a metro sub-journey and convert it into legs with expected clock times.
    /// `entryMin` is the arrival at the boarding station; the expected first-boarding
    /// wait (entry line `headway/2`) is added before the first ride.
    private static func metroSegment(from: String, to: String, entryMin: Int,
                                     graph: MetroGraph, headways: [String: Int]) -> MetroSegment? {
        guard from != to else {
            return MetroSegment(legs: [], transfers: [], arrMin: entryMin)
        }
        guard let path = graph.shortestPathByTime(from: from, to: to), !path.edges.isEmpty else { return nil }

        // Entry first-boarding wait — the first edge is a ride; MetroGraph folds wait
        // only into transfer edges, not the initial boarding.
        let entryLine: String = {
            if case let .ride(line) = path.edges[0].kind { return line }
            return ""
        }()
        let entryWait = (headways[entryLine] ?? 0) / 2

        // Clock minute at each station along the path.
        var arrAt = [Int](repeating: 0, count: path.stations.count)
        arrAt[0] = entryMin + entryWait
        for i in 0..<path.edges.count {
            arrAt[i + 1] = arrAt[i] + Int(path.edges[i].minutes.rounded())
        }

        // Split into per-line ride legs; transfer edges emit Transfer entries.
        var legs: [Leg] = []
        var transfers: [Transfer] = []
        var legStart = 0
        var legLine: String = entryLine
        func flushLeg(end: Int) {
            guard end > legStart else { return }
            let a = path.stations[legStart], b = path.stations[end]
            legs.append(Leg(mode: .metro, line: legLine,
                            fromStation: a, fromName: graph.stationName(a) ?? a,
                            toStation: b, toName: graph.stationName(b) ?? b,
                            depMin: arrAt[legStart], arrMin: arrAt[end],
                            delayMin: nil, source: "frequency"))
        }
        for i in 0..<path.edges.count {
            switch path.edges[i].kind {
            case .ride(let line):
                if legs.isEmpty && legStart == 0 { legLine = line }   // first leg's line
                if i == legStart { legLine = line }
            case .transfer(_, _, let walkMin, _):
                flushLeg(end: i)
                let at = path.stations[i]
                transfers.append(Transfer(at: at, atName: graph.stationName(at) ?? at, walkMin: walkMin))
                legStart = i + 1
                if i + 1 < path.edges.count, case let .ride(line) = path.edges[i + 1].kind { legLine = line }
            }
        }
        flushLeg(end: path.stations.count - 1)
        return MetroSegment(legs: legs, transfers: transfers, arrMin: arrAt[path.stations.count - 1])
    }

    // MARK: - Helpers

    private static func traLeg(_ l: TimetableRouter.Leg) -> Leg {
        Leg(mode: .tra, line: l.trainNo,
            fromStation: l.fromStation, fromName: l.fromName,
            toStation: l.toStation, toName: l.toName,
            depMin: l.depMin, arrMin: l.arrMin,
            delayMin: l.delayMin, source: l.live ? "live" : "scheduled")
    }

    /// Min-headway per line at the band containing `minuteOfDay` on `queryDate`.
    private static func headwayMin(at minuteOfDay: Int, queryDate: Date, metro: MetroData) -> [String: Int] {
        MetroTools.headwayByLine(frequency: metro.frequency, now: date(at: minuteOfDay, on: queryDate))
            .mapValues { $0.0 }
    }

    private static func metroGraph(at minuteOfDay: Int, queryDate: Date, metro: MetroData) -> MetroGraph {
        MetroGraph(stationOfRoute: metro.stationOfRoute, s2s: metro.s2s,
                   lineTransfer: metro.lineTransfer,
                   headwayByLine: headwayMin(at: minuteOfDay, queryDate: queryDate, metro: metro))
    }

    /// A Date on `day` (Asia/Taipei) at the given minute-of-day (wraps past midnight).
    private static func date(at minuteOfDay: Int, on day: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let mod = ((minuteOfDay % 1440) + 1440) % 1440
        return cal.startOfDay(for: day).addingTimeInterval(Double(mod) * 60)
    }
}
