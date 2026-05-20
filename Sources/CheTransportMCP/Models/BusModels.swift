// Sources/CheTransportMCP/Models/BusModels.swift
import Foundation

/// TDX-supported bus operating cities. Raw value matches the `{City}` URL path
/// segment used in TDX bus endpoints (e.g. `/v2/Bus/Route/City/Taipei/...`).
enum BusCity: String, CaseIterable, Codable {
    case Taipei
    case NewTaipei
    case Taoyuan
    case Taichung
    case Tainan
    case Kaohsiung
    case Keelung
    case Hsinchu          // 新竹市
    case HsinchuCounty    // 新竹縣
    case MiaoliCounty
    case ChanghuaCounty
    case NantouCounty
    case YunlinCounty
    case ChiayiCounty
    case Chiayi           // 嘉義市
    case PingtungCounty
    case YilanCounty
    case HualienCounty
    case TaitungCounty
    case KinmenCounty
    case PenghuCounty
    case LienchiangCounty

    var displayName: String {
        switch self {
        case .Taipei: return "臺北市"
        case .NewTaipei: return "新北市"
        case .Taoyuan: return "桃園市"
        case .Taichung: return "臺中市"
        case .Tainan: return "臺南市"
        case .Kaohsiung: return "高雄市"
        case .Keelung: return "基隆市"
        case .Hsinchu: return "新竹市"
        case .HsinchuCounty: return "新竹縣"
        case .MiaoliCounty: return "苗栗縣"
        case .ChanghuaCounty: return "彰化縣"
        case .NantouCounty: return "南投縣"
        case .YunlinCounty: return "雲林縣"
        case .ChiayiCounty: return "嘉義縣"
        case .Chiayi: return "嘉義市"
        case .PingtungCounty: return "屏東縣"
        case .YilanCounty: return "宜蘭縣"
        case .HualienCounty: return "花蓮縣"
        case .TaitungCounty: return "臺東縣"
        case .KinmenCounty: return "金門縣"
        case .PenghuCounty: return "澎湖縣"
        case .LienchiangCounty: return "連江縣"
        }
    }
}

struct BusRoute: Codable {
    let routeUID: String
    let routeID: String?
    let routeName: LocalizedName
    let departureStopNameZh: String?
    let destinationStopNameZh: String?

    enum CodingKeys: String, CodingKey {
        case routeUID = "RouteUID"
        case routeID = "RouteID"
        case routeName = "RouteName"
        case departureStopNameZh = "DepartureStopNameZh"
        case destinationStopNameZh = "DestinationStopNameZh"
    }
}

struct BusStop: Codable {
    let stopUID: String
    let stopID: String?
    let stopName: LocalizedName
    let stopPosition: RailPosition?

    enum CodingKeys: String, CodingKey {
        case stopUID = "StopUID"
        case stopID = "StopID"
        case stopName = "StopName"
        case stopPosition = "StopPosition"
    }
}

struct BusArrival: Codable {
    let stopUID: String?
    let stopID: String?
    let routeUID: String?
    let routeName: LocalizedName?
    let direction: Int?
    /// Seconds until arrival. May be missing when StopStatus indicates "not in service".
    let estimateTime: Int?
    /// 0=normal, 1=出車, 2=交管不停靠, 3=末班車已過, 4=今日未營運, 5=末班車已過站, 6=GPS定位異常
    let stopStatus: Int?

    enum CodingKeys: String, CodingKey {
        case stopUID = "StopUID"
        case stopID = "StopID"
        case routeUID = "RouteUID"
        case routeName = "RouteName"
        case direction = "Direction"
        case estimateTime = "EstimateTime"
        case stopStatus = "StopStatus"
    }
}

struct BusLivePosition: Codable {
    let plateNumb: String?
    let routeUID: String?
    let routeName: LocalizedName?
    let direction: Int?
    let busPosition: RailPosition?

    enum CodingKeys: String, CodingKey {
        case plateNumb = "PlateNumb"
        case routeUID = "RouteUID"
        case routeName = "RouteName"
        case direction = "Direction"
        case busPosition = "BusPosition"
    }
}

/// Entry in `/v2/Bus/StopOfRoute/City/{City}` — used by `bus_find_routes` to
/// intersect O/D candidate routes.
struct BusStopOfRoute: Codable {
    let routeUID: String
    let routeName: LocalizedName
    let direction: Int?
    let stops: [BusStopOfRouteStop]

    enum CodingKeys: String, CodingKey {
        case routeUID = "RouteUID"
        case routeName = "RouteName"
        case direction = "Direction"
        case stops = "Stops"
    }
}

struct BusStopOfRouteStop: Codable {
    let stopUID: String
    let stopID: String?
    let stopName: LocalizedName

    enum CodingKeys: String, CodingKey {
        case stopUID = "StopUID"
        case stopID = "StopID"
        case stopName = "StopName"
    }
}
