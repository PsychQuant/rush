// Sources/CheTransportMCP/Models/TrafficModels.swift
import Foundation

/// Live freeway traffic snapshot. TDX's `Live/Freeway` is section-based: one
/// entry per road section with its current travel time, speed and congestion.
struct FreewayLive: Codable {
    let sectionID: String?
    let travelTime: Int?             // seconds for this section
    let travelSpeed: Double?         // km/h
    let congestionLevelID: String?   // numeric level as string ("1"…"5")
    let congestionLevel: String?     // text level ("順暢", "車多", "壅塞"…)
    let dataCollectTime: String?

    enum CodingKeys: String, CodingKey {
        case sectionID = "SectionID"
        case travelTime = "TravelTime"
        case travelSpeed = "TravelSpeed"
        case congestionLevelID = "CongestionLevelID"
        case congestionLevel = "CongestionLevel"
        case dataCollectTime = "DataCollectTime"
    }
}

struct TrafficIncident: Codable {
    let newsID: String?
    let title: String?
    let newsURL: String?
    let description: String?       // absent in freeway News; present in other news datasets
    let startTime: String?
    let endTime: String?
    let roadName: String?
    let publishTime: String?

    enum CodingKeys: String, CodingKey {
        case newsID = "NewsID"
        case title = "Title"
        case newsURL = "NewsURL"
        case description = "Description"
        case startTime = "StartTime"
        case endTime = "EndTime"
        case roadName = "RoadName"
        case publishTime = "PublishTime"
    }
}

struct TrafficCCTV: Codable {
    let cctvID: String
    let roadID: String?
    let roadName: String?
    let videoStreamURL: String?
    let videoImageURL: String?
    let positionLon: Double?        // TDX puts coordinates at the top level, not in a Position object
    let positionLat: Double?
    let surveillanceDescription: String?

    enum CodingKeys: String, CodingKey {
        case cctvID = "CCTVID"
        case roadID = "RoadID"
        case roadName = "RoadName"
        case videoStreamURL = "VideoStreamURL"
        case videoImageURL = "VideoImageURL"
        case positionLon = "PositionLon"
        case positionLat = "PositionLat"
        case surveillanceDescription = "SurveillanceDescription"
    }
}
