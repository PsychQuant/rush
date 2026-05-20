// Sources/CheTransportMCP/Models/RailModels.swift
import Foundation

struct LocalizedName: Codable {
    let zhTw: String?
    let en: String?

    enum CodingKeys: String, CodingKey {
        case zhTw = "Zh_tw"
        case en = "En"
    }
}

struct RailPosition: Codable {
    let positionLat: Double
    let positionLon: Double

    enum CodingKeys: String, CodingKey {
        case positionLat = "PositionLat"
        case positionLon = "PositionLon"
    }
}

struct RailStation: Codable {
    let stationID: String
    let stationName: LocalizedName
    let stationPosition: RailPosition?

    enum CodingKeys: String, CodingKey {
        case stationID = "StationID"
        case stationName = "StationName"
        case stationPosition = "StationPosition"
    }
}

struct RailTrainInfo: Codable {
    let trainNo: String
    let trainTypeName: LocalizedName?

    enum CodingKeys: String, CodingKey {
        case trainNo = "TrainNo"
        case trainTypeName = "TrainTypeName"
    }
}

struct RailStopTime: Codable {
    let stationID: String
    let stationName: LocalizedName
    let arrivalTime: String?
    let departureTime: String?

    enum CodingKeys: String, CodingKey {
        case stationID = "StationID"
        case stationName = "StationName"
        case arrivalTime = "ArrivalTime"
        case departureTime = "DepartureTime"
    }
}

struct RailODFare: Codable {
    let trainInfo: RailTrainInfo
    let stopTimes: [RailStopTime]

    enum CodingKeys: String, CodingKey {
        case trainInfo = "TrainInfo"
        case stopTimes = "StopTimes"
    }
}

struct RailLiveTrain: Codable {
    let trainNo: String
    let stationID: String?
    let delayTime: Int?

    enum CodingKeys: String, CodingKey {
        case trainNo = "TrainNo"
        case stationID = "StationID"
        case delayTime = "DelayTime"
    }
}

enum RailSystem: String, CaseIterable, Codable {
    case TRA, THSR, TRTC, TYMC, KRTC, TMRT, NTDLRT, KLRT

    var displayName: String {
        switch self {
        case .TRA: return "台鐵"
        case .THSR: return "高鐵"
        case .TRTC: return "台北捷運"
        case .TYMC: return "桃園捷運"
        case .KRTC: return "高雄捷運"
        case .TMRT: return "台中捷運"
        case .NTDLRT: return "新北捷運"
        case .KLRT: return "高雄輕軌"
        }
    }

    var apiPath: String {
        switch self {
        case .TRA: return "v3/Rail/TRA"
        case .THSR: return "v3/Rail/THSR"
        case .TRTC: return "v2/Rail/Metro/TRTC"
        case .TYMC: return "v2/Rail/Metro/TYMC"
        case .KRTC: return "v2/Rail/Metro/KRTC"
        case .TMRT: return "v2/Rail/Metro/TMRT"
        case .NTDLRT: return "v2/Rail/Metro/NTDLRT"
        case .KLRT: return "v2/Rail/Metro/KLRT"
        }
    }
}
