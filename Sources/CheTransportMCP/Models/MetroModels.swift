// Sources/CheTransportMCP/Models/MetroModels.swift
import Foundation

// Codable models for the four TDX metro routing datasets
// (`v2/Rail/Metro/{StationOfRoute,S2STravelTime,Frequency,Line}/{Operator}`).
// Field names mirror the live TDX payloads captured from TRTC (板南線); see the
// matching fixtures under Tests/CheTransportMCPTests/Fixtures/. `LocalizedName`
// (Zh_tw/En) is shared with the rail models.

// MARK: - StationOfRoute

/// One route (a single line + direction) and the ordered stations it serves.
/// Direct O/D routing finds the route(s) whose `stations` contain both endpoints.
struct MetroStationOfRoute: Codable {
    let lineID: String?
    let lineNo: String?
    let routeID: String?
    let direction: Int?
    let lineName: LocalizedName?
    let routeName: LocalizedName?
    let stations: [MetroRouteStation]

    enum CodingKeys: String, CodingKey {
        case lineID = "LineID"
        case lineNo = "LineNo"
        case routeID = "RouteID"
        case direction = "Direction"
        case lineName = "LineName"
        case routeName = "RouteName"
        case stations = "Stations"
    }
}

struct MetroRouteStation: Codable {
    let sequence: Int
    let stationID: String
    let stationName: LocalizedName

    enum CodingKeys: String, CodingKey {
        case sequence = "Sequence"
        case stationID = "StationID"
        case stationName = "StationName"
    }
}

// MARK: - S2STravelTime

/// Station-to-station travel times for one route. `travelTimes` lists the
/// consecutive segments; the segment between two stations carries `runTime`
/// (moving seconds) and `stopTime` (dwell seconds).
struct MetroS2STravelTime: Codable {
    let lineID: String?
    let lineNo: String?
    let routeID: String?
    let travelTimes: [MetroTravelTime]

    enum CodingKeys: String, CodingKey {
        case lineID = "LineID"
        case lineNo = "LineNo"
        case routeID = "RouteID"
        case travelTimes = "TravelTimes"
    }
}

struct MetroTravelTime: Codable {
    let sequence: Int?
    let fromStationID: String
    let toStationID: String
    let runTime: Int
    let stopTime: Int?

    enum CodingKeys: String, CodingKey {
        case sequence = "Sequence"
        case fromStationID = "FromStationID"
        case toStationID = "ToStationID"
        case runTime = "RunTime"
        case stopTime = "StopTime"
    }
}

// MARK: - Frequency

/// Service headways for one route, scoped to a service day (weekday/holiday)
/// and broken into time-of-day bands.
struct MetroFrequency: Codable {
    let lineID: String?
    let lineNo: String?
    let routeID: String?
    let serviceDay: MetroServiceDay
    let operationTime: MetroOperationTime?
    let headways: [MetroHeadway]

    enum CodingKeys: String, CodingKey {
        case lineID = "LineID"
        case lineNo = "LineNo"
        case routeID = "RouteID"
        case serviceDay = "ServiceDay"
        case operationTime = "OperationTime"
        case headways = "Headways"
    }
}

/// Which calendar days this frequency table applies to. Routing matches the
/// queried weekday against these booleans (national-holiday detection is out of
/// scope for v1 — see MetroTools).
struct MetroServiceDay: Codable {
    let serviceTag: String?
    let monday: Bool
    let tuesday: Bool
    let wednesday: Bool
    let thursday: Bool
    let friday: Bool
    let saturday: Bool
    let sunday: Bool
    let nationalHolidays: Bool?

    enum CodingKeys: String, CodingKey {
        case serviceTag = "ServiceTag"
        case monday = "Monday"
        case tuesday = "Tuesday"
        case wednesday = "Wednesday"
        case thursday = "Thursday"
        case friday = "Friday"
        case saturday = "Saturday"
        case sunday = "Sunday"
        case nationalHolidays = "NationalHolidays"
    }
}

struct MetroOperationTime: Codable {
    let startTime: String?
    let endTime: String?

    enum CodingKeys: String, CodingKey {
        case startTime = "StartTime"
        case endTime = "EndTime"
    }
}

struct MetroHeadway: Codable {
    let peakFlag: String?
    let startTime: String
    let endTime: String
    let minHeadwayMins: Int
    let maxHeadwayMins: Int

    enum CodingKeys: String, CodingKey {
        case peakFlag = "PeakFlag"
        case startTime = "StartTime"
        case endTime = "EndTime"
        case minHeadwayMins = "MinHeadwayMins"
        case maxHeadwayMins = "MaxHeadwayMins"
    }
}

// MARK: - Line

/// Human-readable line metadata (name + colour) used to enrich routing output.
struct MetroLine: Codable {
    let lineID: String?
    let lineNo: String?
    let lineName: LocalizedName?
    let lineColor: String?

    enum CodingKeys: String, CodingKey {
        case lineID = "LineID"
        case lineNo = "LineNo"
        case lineName = "LineName"
        case lineColor = "LineColor"
    }
}

// MARK: - LineTransfer

/// One inter-line transfer at an interchange station — the graph's transfer edge.
/// `transferTime` is TDX's platform-walk time in minutes (hard data); the same
/// physical station carries a different StationID per line (e.g. 台北車站 = BL12 /
/// R10), and these rows are exactly what bridge those IDs in the routing graph.
struct MetroLineTransfer: Codable {
    let fromLineID: String?
    let fromStationID: String
    let fromStationName: LocalizedName?
    let toLineID: String?
    let toStationID: String
    let toStationName: LocalizedName?
    let isOnSiteTransfer: Int?
    let transferTime: Int
    let transferDescription: String?

    enum CodingKeys: String, CodingKey {
        case fromLineID = "FromLineID"
        case fromStationID = "FromStationID"
        case fromStationName = "FromStationName"
        case toLineID = "ToLineID"
        case toStationID = "ToStationID"
        case toStationName = "ToStationName"
        case isOnSiteTransfer = "IsOnSiteTransfer"
        case transferTime = "TransferTime"
        case transferDescription = "TransferDescription"
    }
}
