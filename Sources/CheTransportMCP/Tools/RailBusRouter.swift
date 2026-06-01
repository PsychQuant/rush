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
