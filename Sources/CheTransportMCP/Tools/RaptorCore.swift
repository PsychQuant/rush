// Sources/CheTransportMCP/Tools/RaptorCore.swift
import Foundation

/// Stage 3c-ii.1 — the unified routing core, built as a **strategy ensemble**, not a
/// single algorithm (the design principle: run several routing strategies in parallel
/// and return the best journey by a dominance rule). The proven composition becomes a
/// *candidate*, not a *replacement* — so the ensemble can never regress below it, while
/// a round-based strategy only ever *adds* reachable journeys (≥2 transfers).
///
/// Internal only this increment: no MCP tool calls it; the five shipped tools are frozen.
enum RaptorCore {

    /// A unified journey. `legs` reuses `MultimodalRouter.Leg` (so equivalence with the
    /// existing routers is a direct field comparison). `transferCount` is derived: legs are
    /// maximal same-line/same-train runs, so every leg boundary is a transfer.
    struct Journey {
        let legs: [MultimodalRouter.Leg]
        let transfers: [MultimodalRouter.Transfer]
        let arrivalMin: Int
        var transferCount: Int { max(0, legs.count - 1) }
        init(legs: [MultimodalRouter.Leg], transfers: [MultimodalRouter.Transfer] = [], arrivalMin: Int) {
            self.legs = legs; self.transfers = transfers; self.arrivalMin = arrivalMin
        }
    }

    /// Already-fetched datasets a strategy routes over. No strategy issues a new TDX fetch.
    struct RoutingInputs {
        let traConnections: [TimetableRouter.Connection]
        let metro: MultimodalRouter.MetroData
        let queryDate: Date
    }

    /// Run every strategy and return the dominant journey: earliest arrival wins; ties broken
    /// by fewer transfers; remaining ties broken stably by registration order (the first
    /// strategy registered). Because `min(by:)` keeps the first of equal-minimum elements and
    /// `compactMap` preserves order, registering the proven floor first makes it win ties.
    static func plan(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfterMin: Int,
                     inputs: RoutingInputs, strategies: [RoutingStrategy]) -> Journey? {
        let candidates = strategies.compactMap {
            $0.plan(from: from, to: to, departAfterMin: departAfterMin, inputs: inputs)
        }
        return candidates.min { a, b in
            a.arrivalMin != b.arrivalMin ? a.arrivalMin < b.arrivalMin
                                         : a.transferCount < b.transferCount
        }
    }
}

/// A routing strategy: given resolved endpoints + inputs, return its best journey or nil.
/// New strategies (CSA, A*, contraction) slot in without changing the selector.
protocol RoutingStrategy {
    func plan(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfterMin: Int,
              inputs: RaptorCore.RoutingInputs) -> RaptorCore.Journey?
}

/// The floor strategy: delegates to the proven TRA↔metro composition (`MultimodalRouter`).
/// It is optimal for ≤1-transfer journeys, so it dominates and the ensemble reproduces
/// `transit_route` exactly. Being a candidate, it makes regression structurally impossible.
struct ComposedStrategy: RoutingStrategy {
    func plan(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfterMin: Int,
              inputs: RaptorCore.RoutingInputs) -> RaptorCore.Journey? {
        guard let it = MultimodalRouter.route(
            from: from, to: to, departAfterMin: departAfterMin,
            traConnections: inputs.traConnections, metro: inputs.metro, queryDate: inputs.queryDate) else { return nil }
        return RaptorCore.Journey(legs: it.legs, transfers: it.transfers, arrivalMin: it.arrMin)
    }
}

/// An abstract multimodal graph the round engine searches. Edges are typed:
/// `trip` (a discrete catchable departure, TRA), `frequency` (board cost `headway/2` +
/// ride, metro), `footpath` (a walk transfer, no boarding). Built from `RoutingInputs`
/// by `RaptorStrategy`, or directly by tests for synthetic reachability cases.
struct RoutingGraph {
    enum EdgeKind {
        case trip(line: String, depMin: Int, arrMin: Int, mode: MultimodalRouter.Mode, source: String)
        case frequency(line: String, headwayMin: Int, rideMin: Int)
        case footpath(walkMin: Int)
    }
    struct Edge { let from: String; let to: String; let kind: EdgeKind }

    let edges: [Edge]
    let nameOf: [String: String]
    private let adjacency: [String: [Edge]]

    init(edges: [Edge], nameOf: [String: String]) {
        self.edges = edges
        self.nameOf = nameOf
        var adj: [String: [Edge]] = [:]
        for e in edges { adj[e.from, default: []].append(e) }
        self.adjacency = adj
    }
    func out(_ node: String) -> [Edge] { adjacency[node] ?? [] }
    func name(_ id: String) -> String { nameOf[id] ?? id }
}

/// Round-based earliest-arrival over a `RoutingGraph`, bounded by `maxRounds` transfers
/// (so at most `maxRounds + 1` boardings). Footpaths relax within a round (no boarding cost).
/// This is the genuine RAPTOR contribution — it generalizes the seam composition to ≥2
/// transfers; `ComposedStrategy` cannot.
enum RaptorEngine {
    static func earliestArrival(graph: RoutingGraph, from: String, to: String,
                                departAfterMin: Int, maxRounds: Int) -> RaptorCore.Journey? {
        var label: [String: Int] = [from: departAfterMin]
        var parent: [String: RoutingGraph.Edge] = [:]
        var frontier: Set<String> = [from]

        func relaxFootpaths(_ seed: Set<String>) -> Set<String> {
            var improved = seed
            var queue = Array(seed)
            while let n = queue.popLast() {
                let t = label[n]!
                for e in graph.out(n) {
                    guard case let .footpath(walk) = e.kind else { continue }
                    let arr = t + walk
                    if arr < (label[e.to] ?? .max) {
                        label[e.to] = arr; parent[e.to] = e
                        improved.insert(e.to); queue.append(e.to)
                    }
                }
            }
            return improved
        }

        frontier = relaxFootpaths(frontier)
        for _ in 0...max(0, maxRounds) {
            var next: Set<String> = []
            for n in frontier {
                let t = label[n]!
                for e in graph.out(n) {
                    let arr: Int?
                    switch e.kind {
                    case .trip(_, let dep, let a, _, _): arr = dep >= t ? a : nil
                    case .frequency(_, let h, let ride): arr = t + h / 2 + ride
                    case .footpath: arr = nil   // handled by relaxFootpaths
                    }
                    if let arr, arr < (label[e.to] ?? .max) {
                        label[e.to] = arr; parent[e.to] = e; next.insert(e.to)
                    }
                }
            }
            if next.isEmpty { break }
            frontier = relaxFootpaths(next)
        }

        guard let arrival = label[to] else { return nil }

        // Reconstruct edge chain from `to` back to `from`.
        var chain: [RoutingGraph.Edge] = []
        var cur = to
        var guardCount = 0
        while cur != from, let e = parent[cur], guardCount < 10_000 {
            chain.append(e); cur = e.from; guardCount += 1
        }
        chain.reverse()

        // Trip / frequency edges become legs; footpath edges become transfers.
        var legs: [MultimodalRouter.Leg] = []
        var transfers: [MultimodalRouter.Transfer] = []
        var clock = departAfterMin
        for e in chain {
            switch e.kind {
            case .trip(let line, let dep, let a, let mode, let source):
                legs.append(MultimodalRouter.Leg(mode: mode, line: line,
                    fromStation: e.from, fromName: graph.name(e.from),
                    toStation: e.to, toName: graph.name(e.to),
                    depMin: dep, arrMin: a, delayMin: nil, source: source))
                clock = a
            case .frequency(let line, let h, let ride):
                let dep = clock + h / 2, a = dep + ride
                legs.append(MultimodalRouter.Leg(mode: .metro, line: line,
                    fromStation: e.from, fromName: graph.name(e.from),
                    toStation: e.to, toName: graph.name(e.to),
                    depMin: dep, arrMin: a, delayMin: nil, source: "frequency"))
                clock = a
            case .footpath(let walk):
                transfers.append(MultimodalRouter.Transfer(at: e.from, atName: graph.name(e.from), walkMin: walk))
                clock += walk
            }
        }
        return RaptorCore.Journey(legs: legs, transfers: transfers, arrivalMin: arrival)
    }
}

/// The round-based strategy. Builds an (intentionally safe-over-counting) `RoutingGraph`
/// from the inputs — TRA connections as discrete trips, metro adjacency as per-hop
/// frequency edges, `InterchangeRegistry` as footpaths — and runs `RaptorEngine`. Its
/// value is reaching ≥2-transfer destinations; for ≤1-transfer journeys it never beats
/// `ComposedStrategy` (it cannot under-count), so the ensemble stays equivalent.
struct RaptorStrategy: RoutingStrategy {
    let maxRounds: Int
    init(maxRounds: Int = 3) { self.maxRounds = maxRounds }

    func plan(from: MultimodalRouter.Stop, to: MultimodalRouter.Stop, departAfterMin: Int,
              inputs: RaptorCore.RoutingInputs) -> RaptorCore.Journey? {
        var edges: [RoutingGraph.Edge] = []
        var names: [String: String] = [:]

        // TRA discrete trip edges (live-adjusted), from the connection set.
        for c in inputs.traConnections {
            names[c.fromStation] = c.fromName; names[c.toStation] = c.toName
            edges.append(.init(from: c.fromStation, to: c.toStation,
                kind: .trip(line: c.trainNo, depMin: c.depMin, arrMin: c.arrMin,
                            mode: .tra, source: c.live ? "live" : "scheduled")))
        }

        // Metro per-hop frequency edges (over-counts wait per hop — safe: never under-counts).
        let headways = MetroTools.headwayByLine(frequency: inputs.metro.frequency,
                                                now: inputs.queryDate).mapValues { $0.0 }
        var s2sMin: [String: Int] = [:]
        for el in inputs.metro.s2s {
            for tt in el.travelTimes { s2sMin["\(tt.fromStationID)>\(tt.toStationID)"] = (tt.runTime + (tt.stopTime ?? 0)) / 60 }
        }
        for line in inputs.metro.stationOfRoute {
            let lid = line.lineID ?? line.lineNo ?? ""
            let h = headways[lid] ?? 0
            let st = line.stations
            for s in st { names[s.stationID] = s.stationName.zhTw ?? s.stationID }
            guard st.count >= 2 else { continue }
            for i in 0..<(st.count - 1) {
                let a = st[i].stationID, b = st[i + 1].stationID
                let ride = s2sMin["\(a)>\(b)"] ?? s2sMin["\(b)>\(a)"]
                guard let ride else { continue }
                edges.append(.init(from: a, to: b, kind: .frequency(line: lid, headwayMin: h, rideMin: ride)))
                edges.append(.init(from: b, to: a, kind: .frequency(line: lid, headwayMin: h, rideMin: ride)))
            }
        }

        // Cross-system footpaths from the curated registry (both directions).
        for ix in InterchangeRegistry.entries {
            for node in ix.trtcStationIDs {
                edges.append(.init(from: ix.traStationID, to: node, kind: .footpath(walkMin: ix.walkMin)))
                edges.append(.init(from: node, to: ix.traStationID, kind: .footpath(walkMin: ix.walkMin)))
            }
        }

        let graph = RoutingGraph(edges: edges, nameOf: names)
        // Try every origin/destination platform id (metro stops expose several).
        var best: RaptorCore.Journey?
        for o in from.ids {
            for d in to.ids {
                if let j = RaptorEngine.earliestArrival(graph: graph, from: o, to: d,
                                                        departAfterMin: departAfterMin, maxRounds: maxRounds),
                   best == nil || j.arrivalMin < best!.arrivalMin {
                    best = j
                }
            }
        }
        return best
    }
}
