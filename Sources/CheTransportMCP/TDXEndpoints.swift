// Sources/CheTransportMCP/TDXEndpoints.swift
import Foundation

/// Single source of truth for every TDX API endpoint path.
///
/// Production code (Tools / Models) resolves paths through the builder
/// functions here instead of embedding string literals, and contract tests
/// walk `allContractCases` so that every registered endpoint is covered by a
/// live check **without a separately maintained list**. Adding an endpoint is
/// one action: add a builder + a contract case here.
///
/// Path conventions differ across TDX services — which is exactly why they
/// belong in one audited place:
///
///   - TRA:   `v3`, dataset **after** the system   → `v3/Rail/TRA/{Dataset}`
///   - THSR:  `v2`, dataset **after** the system   → `v2/Rail/THSR/{Dataset}`
///            (NOT `v3`, and timetable dataset is `DailyTimetable` — fixes #4)
///   - Metro: `v2`, dataset **before** the operator → `v2/Rail/Metro/{Dataset}/{Operator}`
///            (operator-last ordering was 404 — fixes #4 metro finding)
///   - Parking: served under `v1`, not `v2`.
enum TDXEndpoints {

    // MARK: - Rail

    /// Station list for a rail system. TRA/THSR put the dataset after the
    /// system code; metros put the dataset before the operator code.
    static func railStation(_ sys: RailSystem) -> String {
        switch sys {
        case .TRA:  return "v3/Rail/TRA/Station"
        case .THSR: return "v2/Rail/THSR/Station"
        default:    return "v2/Rail/Metro/Station/\(sys.rawValue)"
        }
    }

    /// O/D daily timetable. TRA uses `v3` + `DailyTrainTimetable`; THSR uses
    /// `v2` + `DailyTimetable` (different dataset name). Only TRA/THSR expose
    /// this dataset — callers guard before invoking; metros fall back to the
    /// TRA shape but are never routed here.
    static func railTimetableOD(_ sys: RailSystem, from: String, to: String, date: String) -> String {
        switch sys {
        case .THSR: return "v2/Rail/THSR/DailyTimetable/OD/\(from)/to/\(to)/\(date)"
        default:    return "v3/Rail/TRA/DailyTrainTimetable/OD/\(from)/to/\(to)/\(date)"
        }
    }

    /// Live train-delay board (collection). **TRA only** — v3 dropped the
    /// `/Train/{no}` path-param form (404), so callers narrow to one train with
    /// a `$filter=TrainNo` query; and TDX provides no THSR train live board.
    static func railTrainLiveBoard() -> String { "v3/Rail/TRA/TrainLiveBoard" }

    /// Live arrivals board for one TRA station (the `/Station/{id}` path-param
    /// form still works on v3). **TRA only** — TDX provides no THSR station
    /// live board.
    static func railStationLiveBoard(stationID: String) -> String {
        "v3/Rail/TRA/StationLiveBoard/Station/\(stationID)"
    }

    // MARK: - Air

    static func airAirport() -> String { "v2/Air/Airport" }
    static func airFIDS(direction: String, airport: String) -> String {
        "v2/Air/FIDS/Airport/\(direction)/\(airport)"
    }

    // MARK: - Bus (city-scoped)

    static func busRoute(_ city: String) -> String { "v2/Bus/Route/City/\(city)" }
    static func busStop(_ city: String) -> String { "v2/Bus/Stop/City/\(city)" }
    static func busStopOfRoute(_ city: String) -> String { "v2/Bus/StopOfRoute/City/\(city)" }
    static func busEstimatedTimeOfArrival(_ city: String) -> String { "v2/Bus/EstimatedTimeOfArrival/City/\(city)" }
    static func busRealTimeNearStop(_ city: String, route: String) -> String { "v2/Bus/RealTimeNearStop/City/\(city)/\(route)" }

    // MARK: - Bike (city-scoped)

    static func bikeStation(_ city: String) -> String { "v2/Bike/Station/City/\(city)" }
    static func bikeAvailability(_ city: String) -> String { "v2/Bike/Availability/City/\(city)" }

    // MARK: - Traffic

    static func trafficFreewayLive() -> String { "v2/Road/Traffic/Live/Freeway" }
    /// Freeway traffic news / incidents. The bare `v2/Road/Traffic/News` was
    /// 404 (#4 root cause); the live news dataset lives under `Live/News/Freeway`
    /// (confirmed by live probe).
    static func trafficNews() -> String { "v2/Road/Traffic/Live/News/Freeway" }
    static func trafficCCTVHighway() -> String { "v2/Road/Traffic/CCTV/Highway" }

    // MARK: - Parking (note: served under v1)

    static func parkingCarPark(_ city: String) -> String { "v1/Parking/OffStreet/CarPark/City/\(city)" }
    static func parkingAvailability(_ city: String) -> String { "v1/Parking/OffStreet/ParkingAvailability/City/\(city)" }
}

// MARK: - Contract-test enumeration

extension TDXEndpoints {

    /// One enumerable record per non-static endpoint, carrying a concrete path
    /// (representative parameters baked in) plus a strict decode check. Contract
    /// tests iterate this; production never reads it. Static endpoints
    /// (e.g. `rail_list_systems`, which returns a client-side hardcoded list)
    /// have no registry path and are intentionally absent.
    struct ContractCase {
        /// Stable identifier, e.g. `rail.THSR.station`.
        let key: String
        /// Transport mode, for grouping in test reports.
        let mode: String
        /// Concrete request path with representative parameters substituted.
        let path: String
        /// Throws if `data` does not decode into the endpoint's declared model.
        let decode: (Data) throws -> Void
    }

    /// Representative date (Asia/Taipei today) for timetable contract cases.
    private static func sampleDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f.string(from: Date())
    }

    /// Strict array decode — throws on schema drift (unlike production's `try?`).
    private static func arrayDecoder<T: Decodable>(_ type: T.Type) -> (Data) throws -> Void {
        { data in _ = try JSONDecoder().decode([T].self, from: data) }
    }

    /// Strict decode for endpoints whose body may be a bare array OR a wrapped
    /// object (`{…metadata…, "<Dataset>": [...] }` — TDX Road/Traffic, Parking).
    /// Mirrors production's `TDXDecode.list` but THROWS on schema drift so the
    /// contract catches model mismatches.
    private static func wrappedArrayDecoder<T: Decodable>(_ type: T.Type) -> (Data) throws -> Void {
        { data in
            let decoder = JSONDecoder()
            if (try? decoder.decode([T].self, from: data)) != nil { return }
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let dict = obj as? [String: Any] else {
                throw TDXError.decoding("expected bare array or wrapped object, got \(Swift.type(of: obj))")
            }
            guard let arr = dict.values.first(where: { $0 is [Any] }) as? [Any],
                  let arrData = try? JSONSerialization.data(withJSONObject: arr) else {
                throw TDXError.decoding("wrapped object has no array field")
            }
            _ = try decoder.decode([T].self, from: arrData)
        }
    }

    /// Rail station lists arrive wrapped (`{"Stations":[…]}`, TRA v3) or bare
    /// (metros / THSR). Accept either; throw if neither decodes.
    private static func decodeStationListStrict(_ data: Data) throws {
        struct Wrapped: Decodable { let Stations: [RailStation] }
        if (try? JSONDecoder().decode(Wrapped.self, from: data)) != nil { return }
        _ = try JSONDecoder().decode([RailStation].self, from: data)
    }

    /// Several tools pass the TDX body through raw (rail timetable / live
    /// boards) — production decodes no model for them, so the
    /// contract only asserts the body is well-formed JSON (object or array). The
    /// path-correctness layers (not-404, 200) still apply; this just avoids
    /// imposing a stricter shape than production ever validates.
    private static func decodeAnyJSON(_ data: Data) throws {
        _ = try JSONSerialization.jsonObject(with: data)
    }

    /// Every non-static endpoint, with a representative concrete path.
    static var allContractCases: [ContractCase] {
        let date = sampleDate()
        let city = "Taipei"
        var cases: [ContractCase] = []

        // Rail — station list for all 8 systems (rail_search_stations fans out
        // to every system, so each path must be correct).
        for sys in RailSystem.allCases {
            cases.append(ContractCase(
                key: "rail.\(sys.rawValue).station",
                mode: "rail",
                path: railStation(sys),
                decode: decodeStationListStrict
            ))
        }
        // Rail — TRA/THSR O/D timetable (both systems expose it). Production
        // passes these through raw (no model decode), so the contract validates
        // well-formed JSON; the not-404 / 200 layers guard path correctness.
        for sys in [RailSystem.TRA, .THSR] {
            cases.append(ContractCase(
                key: "rail.\(sys.rawValue).timetableOD",
                mode: "rail",
                path: railTimetableOD(sys, from: "1000", to: "1070", date: date),
                decode: decodeAnyJSON
            ))
        }
        // Rail — live boards are TRA-only (TDX provides none for THSR). Raw
        // pass-through, so the contract validates well-formed JSON.
        cases.append(ContractCase(
            key: "rail.TRA.trainLiveBoard", mode: "rail",
            path: railTrainLiveBoard(), decode: decodeAnyJSON))
        cases.append(ContractCase(
            key: "rail.TRA.stationLiveBoard", mode: "rail",
            path: railStationLiveBoard(stationID: "1000"), decode: decodeAnyJSON))

        // Air
        cases.append(ContractCase(key: "air.airport", mode: "air",
            path: airAirport(), decode: arrayDecoder(Airport.self)))
        cases.append(ContractCase(key: "air.fids", mode: "air",
            path: airFIDS(direction: "Departure", airport: "TPE"), decode: arrayDecoder(FlightInfo.self)))

        // Bus (representative city)
        cases.append(ContractCase(key: "bus.route", mode: "bus",
            path: busRoute(city), decode: arrayDecoder(BusRoute.self)))
        cases.append(ContractCase(key: "bus.stop", mode: "bus",
            path: busStop(city), decode: arrayDecoder(BusStop.self)))
        cases.append(ContractCase(key: "bus.stopOfRoute", mode: "bus",
            path: busStopOfRoute(city), decode: arrayDecoder(BusStopOfRoute.self)))
        cases.append(ContractCase(key: "bus.eta", mode: "bus",
            path: busEstimatedTimeOfArrival(city), decode: arrayDecoder(BusArrival.self)))
        cases.append(ContractCase(key: "bus.realTimeNearStop", mode: "bus",
            path: busRealTimeNearStop(city, route: "299"), decode: arrayDecoder(BusLivePosition.self)))

        // Bike (representative city)
        cases.append(ContractCase(key: "bike.station", mode: "bike",
            path: bikeStation(city), decode: arrayDecoder(BikeStation.self)))
        cases.append(ContractCase(key: "bike.availability", mode: "bike",
            path: bikeAvailability(city), decode: arrayDecoder(BikeAvailability.self)))

        // Traffic — v2 Road/Traffic wraps the data array in an object.
        cases.append(ContractCase(key: "traffic.freewayLive", mode: "traffic",
            path: trafficFreewayLive(), decode: wrappedArrayDecoder(FreewayLive.self)))
        cases.append(ContractCase(key: "traffic.news", mode: "traffic",
            path: trafficNews(), decode: wrappedArrayDecoder(TrafficIncident.self)))
        cases.append(ContractCase(key: "traffic.cctv", mode: "traffic",
            path: trafficCCTVHighway(), decode: wrappedArrayDecoder(TrafficCCTV.self)))

        // Parking (representative city) — v1 Parking wraps the data array.
        cases.append(ContractCase(key: "parking.carPark", mode: "parking",
            path: parkingCarPark(city), decode: wrappedArrayDecoder(ParkingLot.self)))
        cases.append(ContractCase(key: "parking.availability", mode: "parking",
            path: parkingAvailability(city), decode: wrappedArrayDecoder(ParkingAvailability.self)))

        return cases
    }
}
