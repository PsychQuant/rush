// Sources/Rush/Tools/MetroGraph.swift
import Foundation

/// In-memory routing graph for a single metro system, plus shortest-path search.
///
/// Nodes are line-prefixed StationIDs (so 台北車站 is two nodes — BL12 and R10 —
/// joined by a transfer edge). Edges:
///   - **ride**: adjacent stations on one line (from StationOfRoute), weighted by
///     S2STravelTime (RunTime + StopTime). Bidirectional; segment time is looked
///     up direction-agnostically because TDX stores S2S in one direction only.
///   - **transfer**: an interchange (from LineTransfer), weighted by the walk time
///     plus an estimated boarding wait (destination line's headway / 2).
///
/// Built on demand per query; the underlying datasets are 24h-cached by TDXClient,
/// so there is no separate graph cache (the graph itself is microseconds to build
/// for a ~100-station system).
struct MetroGraph {

    enum EdgeKind {
        case ride(line: String)
        case transfer(fromLine: String, toLine: String, walkMin: Int, waitMin: Int)
    }

    struct Edge {
        let to: String
        let minutes: Double
        let kind: EdgeKind
        var isTransfer: Bool { if case .transfer = kind { return true }; return false }
    }

    /// A resolved route: the ordered station IDs and the edge taken between each
    /// consecutive pair (so `edges.count == stations.count - 1`).
    struct Path {
        let stations: [String]
        let edges: [Edge]
        let totalMinutes: Double
        let transferCount: Int
    }

    private let adjacency: [String: [Edge]]
    private let names: [String: LocalizedName]

    func stationName(_ id: String) -> String? { names[id]?.zhTw ?? names[id]?.en }

    // MARK: - Build

    init(stationOfRoute: [MetroStationOfRoute],
         s2s: [MetroS2STravelTime],
         lineTransfer: [MetroLineTransfer],
         headwayByLine: [String: Int]) {

        var names: [String: LocalizedName] = [:]

        // Segment minutes, looked up by directed pair but registered both ways —
        // S2S stores only one direction and adjacent-station run-time is symmetric.
        var segMin: [String: Double] = [:]
        func key(_ a: String, _ b: String) -> String { "\(a)>\(b)" }
        for el in s2s {
            for tt in el.travelTimes {
                let m = Double(tt.runTime + (tt.stopTime ?? 0)) / 60.0
                if segMin[key(tt.fromStationID, tt.toStationID)] == nil { segMin[key(tt.fromStationID, tt.toStationID)] = m }
                if segMin[key(tt.toStationID, tt.fromStationID)] == nil { segMin[key(tt.toStationID, tt.fromStationID)] = m }
            }
        }

        var adj: [String: [Edge]] = [:]

        // Ride edges from same-line adjacency. Dedup by (from,to,line) keeping the
        // first (routes BL-1/BL-2 share adjacencies).
        var rideSeen: Set<String> = []
        for r in stationOfRoute {
            let line = r.lineID ?? r.lineNo ?? ""
            for st in r.stations where names[st.stationID] == nil { names[st.stationID] = st.stationName }
            let st = r.stations
            guard st.count >= 2 else { continue }
            for i in 0..<(st.count - 1) {
                let a = st[i].stationID, b = st[i + 1].stationID
                guard let m = segMin[key(a, b)] else { continue }   // no S2S → no traversable edge
                for (x, y) in [(a, b), (b, a)] {
                    let dedup = "\(x)>\(y)|\(line)"
                    if rideSeen.contains(dedup) { continue }
                    rideSeen.insert(dedup)
                    adj[x, default: []].append(Edge(to: y, minutes: m, kind: .ride(line: line)))
                }
            }
        }

        // Transfer edges (both directions; wait = boarded line's headway / 2).
        var xferSeen: Set<String> = []
        for t in lineTransfer {
            if names[t.fromStationID] == nil { names[t.fromStationID] = t.fromStationName }
            if names[t.toStationID] == nil { names[t.toStationID] = t.toStationName }
            let fl = t.fromLineID ?? "", tl = t.toLineID ?? ""
            let specs = [(t.fromStationID, t.toStationID, fl, tl), (t.toStationID, t.fromStationID, tl, fl)]
            for (frm, to, fromLine, toLine) in specs {
                let dedup = "\(frm)>\(to)|\(toLine)"
                if xferSeen.contains(dedup) { continue }
                xferSeen.insert(dedup)
                let waitExact = Double(headwayByLine[toLine] ?? 0) / 2.0
                adj[frm, default: []].append(Edge(
                    to: to, minutes: Double(t.transferTime) + waitExact,
                    kind: .transfer(fromLine: fromLine, toLine: toLine,
                                    walkMin: t.transferTime, waitMin: Int(waitExact.rounded()))))
            }
        }

        self.adjacency = adj
        self.names = names
    }

    // MARK: - Shortest path (two objectives over one generic Dijkstra)

    /// Minimize total travel time.
    func shortestPathByTime(from: String, to: String) -> Path? {
        dijkstra(from: from, to: to, zero: 0.0) { $0 + $1.minutes }
    }

    /// Minimize transfer count, breaking ties by total time.
    func shortestPathByTransfers(from: String, to: String) -> Path? {
        dijkstra(from: from, to: to, zero: TransferCost(transfers: 0, minutes: 0)) {
            TransferCost(transfers: $0.transfers + ($1.isTransfer ? 1 : 0), minutes: $0.minutes + $1.minutes)
        }
    }

    private struct TransferCost: Comparable {
        let transfers: Int
        let minutes: Double
        static func < (l: TransferCost, r: TransferCost) -> Bool {
            l.transfers != r.transfers ? l.transfers < r.transfers : l.minutes < r.minutes
        }
    }

    /// Generic Dijkstra over a comparable accumulated cost. O(V²) extract-min is
    /// fine for a single metro system (~100–200 nodes).
    private func dijkstra<C: Comparable>(from: String, to: String, zero: C, extend: (C, Edge) -> C) -> Path? {
        guard adjacency[from] != nil || from == to else { return nil }
        var dist: [String: C] = [from: zero]
        var prev: [String: (String, Edge)] = [:]
        var visited: Set<String> = []

        while true {
            var u: String?
            var best: C?
            for (node, d) in dist where !visited.contains(node) {
                if best == nil || d < best! { best = d; u = node }
            }
            guard let cur = u else { break }
            if cur == to { break }
            visited.insert(cur)
            for edge in adjacency[cur] ?? [] where !visited.contains(edge.to) {
                let nd = extend(dist[cur]!, edge)
                if dist[edge.to] == nil || nd < dist[edge.to]! {
                    dist[edge.to] = nd
                    prev[edge.to] = (cur, edge)
                }
            }
        }

        guard dist[to] != nil else { return nil }

        var stations = [to]
        var edges: [Edge] = []
        var cur = to
        while let (p, e) = prev[cur] {
            stations.append(p)
            edges.append(e)
            cur = p
        }
        stations.reverse()
        edges.reverse()
        let total = edges.reduce(0.0) { $0 + $1.minutes }
        let transfers = edges.filter { $0.isTransfer }.count
        return Path(stations: stations, edges: edges, totalMinutes: total, transferCount: transfers)
    }
}
