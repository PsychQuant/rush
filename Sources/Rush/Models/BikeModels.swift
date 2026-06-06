// Sources/Rush/Models/BikeModels.swift
import Foundation

/// Bike-share operating cities. TDX bike data spans most of Taiwan;
/// rawValue matches the URL `{City}` segment.
enum BikeCity: String, CaseIterable, Codable {
    case Taipei
    case NewTaipei
    case Taoyuan
    case Taichung
    case Tainan
    case Kaohsiung
    case Hsinchu
    case HsinchuCounty
    case ChanghuaCounty
    case PingtungCounty
    case Chiayi
    case ChiayiCounty
    case MiaoliCounty
    case YilanCounty
    case Keelung
}

/// YouBike service generations. Some cities operate both side-by-side.
enum BikeServiceType: Int, CaseIterable, Codable {
    case youBike1_0 = 1
    case youBike2_0 = 2

    var displayName: String {
        switch self {
        case .youBike1_0: return "YouBike 1.0"
        case .youBike2_0: return "YouBike 2.0"
        }
    }
}

struct BikeStation: Codable {
    let stationUID: String
    let stationID: String?
    let stationName: LocalizedName
    let stationPosition: RailPosition?
    /// 1 = YouBike 1.0, 2 = YouBike 2.0, may be missing for older datasets.
    let serviceType: Int?
    let bikesCapacity: Int?

    enum CodingKeys: String, CodingKey {
        case stationUID = "StationUID"
        case stationID = "StationID"
        case stationName = "StationName"
        case stationPosition = "StationPosition"
        case serviceType = "ServiceType"
        case bikesCapacity = "BikesCapacity"
    }
}

struct BikeAvailability: Codable {
    let stationUID: String
    let stationID: String?
    let serviceStatus: Int?      // 0=停止, 1=營運中, 2=暫停營運
    let availableRentBikes: Int?
    let availableReturnBikes: Int?

    enum CodingKeys: String, CodingKey {
        case stationUID = "StationUID"
        case stationID = "StationID"
        case serviceStatus = "ServiceStatus"
        case availableRentBikes = "AvailableRentBikes"
        case availableReturnBikes = "AvailableReturnBikes"
    }
}
