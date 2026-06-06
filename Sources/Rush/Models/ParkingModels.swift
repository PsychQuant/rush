// Sources/Rush/Models/ParkingModels.swift
import Foundation

/// Cities TDX parking endpoints accept. Coverage is uneven — cities outside
/// the major metros may return empty lists. The enum just enforces a 3-letter
/// path-segment guard; emptiness is not an error per project's "empty ≠ error"
/// invariant.
enum ParkingCity: String, CaseIterable, Codable {
    case Taipei
    case NewTaipei
    case Taoyuan
    case Taichung
    case Tainan
    case Kaohsiung
    case Hsinchu
    case HsinchuCounty
    case Keelung
    case ChanghuaCounty
    case PingtungCounty
    case YilanCounty
    case HualienCounty
    case TaitungCounty
    case ChiayiCounty
    case Chiayi
    case MiaoliCounty
    case NantouCounty
    case YunlinCounty
    case PenghuCounty
    case KinmenCounty
    case LienchiangCounty
}

struct ParkingLot: Codable {
    let carParkID: String
    let carParkName: LocalizedName?
    let address: String?
    let totalSpaces: Int?
    let carParkType: Int?           // 1=路邊 2=立體 3=平面 etc.
    let carParkPosition: RailPosition?

    enum CodingKeys: String, CodingKey {
        case carParkID = "CarParkID"
        case carParkName = "CarParkName"
        case address = "Address"
        case totalSpaces = "TotalSpaces"
        case carParkType = "CarParkType"
        case carParkPosition = "CarParkPosition"
    }
}

struct ParkingAvailability: Codable {
    let carParkID: String
    let availableSpaces: Int?
    /// 0=normal, others vary per city
    let serviceStatus: Int?
    let dataCollectTime: String?

    enum CodingKeys: String, CodingKey {
        case carParkID = "CarParkID"
        case availableSpaces = "AvailableSpaces"
        case serviceStatus = "ServiceStatus"
        case dataCollectTime = "DataCollectTime"
    }
}
