// Sources/CheTransportMCP/Tools/BusRouter.swift
import Foundation

/// Stage 3a: direct-route bus routing (no transfers). Pure assembly over
/// pre-resolved candidate routes + A2 live ETA + Bus/Schedule. The caller
/// (`BusTools.executeBusRoute`) does the I/O (stop resolution, StopOfRoute
/// intersection, A2 + Schedule fetch); this is the deterministic core.
///
/// Board time: A2 live ETA at the origin stop (`source: live`) → next timetabled
/// departure (`source: scheduled`) → headway/2 expected-wait (`source: frequency`).
/// Arrival time: timetable per-stop delta where the route is timetabled
/// (`source: scheduled`); otherwise omitted with a note (never faked).
enum BusRouter {

    /// A direct route serving origin before dest in one direction (pre-filtered).
    struct Candidate {
        let routeUID: String
        let routeName: String
        let subRouteName: String?
        let direction: Int
        let originStopUID: String
        let originStopName: String
        let destStopUID: String
        let destStopName: String
    }

    struct Option {
        let routeName: String
        let subRouteName: String?
        let direction: Int
        let boardStop: String
        let alightStop: String
        let boardInMin: Int?
        let boardSource: String          // live | scheduled | frequency | unknown
        let arrivalClockMin: Int?        // internal sort key (nil = unknown)
        let arrivalTime: String?         // "HH:mm" or nil
        let arrivalSource: String?       // scheduled | nil
        let note: String?
    }

    static func sig(_ routeUID: String, _ direction: Int) -> String { "\(routeUID)|\(direction)" }

    /// `a2BySig`: route+direction → live ETA seconds at the origin stop (only where A2 has one).
    /// `scheduleBySig`: route+direction → its Bus/Schedule entry.
    static func route(candidates: [Candidate],
                      a2BySig: [String: Int],
                      scheduleBySig: [String: BusSchedule],
                      nowMin: Int, departAfterMin: Int, weekday: Int) -> [Option] {
        var options: [Option] = []
        for c in candidates {
            let key = sig(c.routeUID, c.direction)
            let schedule = scheduleBySig[key]
            let trip = schedule.flatMap { nextTrip($0, originUID: c.originStopUID, destUID: c.destStopUID,
                                                   departAfterMin: departAfterMin, weekday: weekday) }

            // --- Board ---
            var boardInMin: Int?
            var boardSource = "unknown"
            var boardClockMin: Int?
            if let etaSec = a2BySig[key], etaSec >= 0 {
                let m = (etaSec + 59) / 60                 // ceil to minutes
                boardInMin = m; boardSource = "live"; boardClockMin = nowMin + m
            } else if let t = trip {
                boardInMin = max(0, t.originDepMin - nowMin); boardSource = "scheduled"; boardClockMin = t.originDepMin
            } else if let s = schedule, let wait = headwayWait(s, at: departAfterMin, weekday: weekday) {
                boardInMin = wait; boardSource = "frequency"; boardClockMin = departAfterMin + wait
            }

            // --- Arrival (timetable ride-time only; else omit) ---
            var arrivalClockMin: Int?
            var arrivalTime: String?
            var arrivalSource: String?
            var note: String?
            if let t = trip, let bc = boardClockMin {
                arrivalClockMin = bc + t.rideMin
                arrivalTime = TimetableRouter.clock(arrivalClockMin!)
                arrivalSource = "scheduled"
            } else {
                note = "此路線無班表抵達時刻（frequency-only 或無資料），僅提供上車預估"
            }

            options.append(Option(
                routeName: c.routeName, subRouteName: c.subRouteName, direction: c.direction,
                boardStop: c.originStopName, alightStop: c.destStopName,
                boardInMin: boardInMin, boardSource: boardSource,
                arrivalClockMin: arrivalClockMin, arrivalTime: arrivalTime, arrivalSource: arrivalSource,
                note: note))
        }

        // Earliest arrival first (known arrivals before unknown), then soonest board.
        return options.sorted { a, b in
            switch (a.arrivalClockMin, b.arrivalClockMin) {
            case let (x?, y?): return x != y ? x < y : (a.boardInMin ?? .max) < (b.boardInMin ?? .max)
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return (a.boardInMin ?? .max) < (b.boardInMin ?? .max)
            }
        }
    }

    // MARK: - Schedule helpers

    private struct TripPick { let originDepMin: Int; let rideMin: Int }

    /// The trip (active on `weekday`) whose origin departure is the earliest at/after
    /// `departAfterMin`, plus its origin→dest ride-time. Falls back to any active trip's
    /// ride-time (≈ constant) when no future departure remains, so a live-boarded leg
    /// still gets an arrival estimate.
    private static func nextTrip(_ s: BusSchedule, originUID: String, destUID: String,
                                 departAfterMin: Int, weekday: Int) -> TripPick? {
        guard let trips = s.timetables else { return nil }
        var future: TripPick?
        var anyRide: Int?
        for trip in trips {
            if let sd = trip.serviceDay, !sd.active(weekday: weekday) { continue }
            guard let o = trip.stopTimes.first(where: { $0.stopUID == originUID }),
                  let d = trip.stopTimes.first(where: { $0.stopUID == destUID }),
                  let oDep = o.departureTime.flatMap(TimetableRouter.minutesOfDay),
                  let dArr = d.arrivalTime.flatMap(TimetableRouter.minutesOfDay) else { continue }
            if let os = o.stopSequence, let ds = d.stopSequence, os >= ds { continue }  // origin must precede dest
            var ride = dArr - oDep
            if ride < 0 { ride += 1440 }
            anyRide = anyRide ?? ride
            if oDep >= departAfterMin, future == nil || oDep < future!.originDepMin {
                future = TripPick(originDepMin: oDep, rideMin: ride)
            }
        }
        if let f = future { return f }
        // No future departure: still expose ride-time (for a live-boarded arrival estimate),
        // with originDepMin = departAfterMin as a neutral placeholder (board comes from A2/headway).
        if let r = anyRide { return TripPick(originDepMin: departAfterMin, rideMin: r) }
        return nil
    }

    /// Expected wait = MinHeadwayMins/2 of the headway band containing `minute`
    /// (active on `weekday`). nil when no band applies.
    private static func headwayWait(_ s: BusSchedule, at minute: Int, weekday: Int) -> Int? {
        guard let bands = s.frequencys else { return nil }
        let band = bands.first { b in
            (b.serviceDay?.active(weekday: weekday) ?? true) && bandContains(b, minute: minute)
        } ?? bands.first { $0.serviceDay?.active(weekday: weekday) ?? true }
        return band.map { max(0, $0.minHeadwayMins) / 2 }
    }

    private static func bandContains(_ b: BusFrequency, minute: Int) -> Bool {
        guard let start = TimetableRouter.minutesOfDay(b.startTime) else { return false }
        var end = TimetableRouter.minutesOfDay(b.endTime) ?? 1440
        if end == 0 { end = 1440 }
        return minute >= start && minute < end
    }
}
