// Sources/CheTransportMCP/Models/TrafficModels.swift
import Foundation

/// Live freeway traffic snapshot. TDX returns one entry per section per direction.
struct FreewayLive: Codable {
    let roadID: String?
    let roadName: String?
    let sectionID: String?
    let direction: Int?              // 0=北上, 1=南下 (per TDX convention)
    let speed: Double?               // km/h
    let travelTime: Int?             // seconds for this section
    let congestionLevel: Int?        // 1=順暢, 2=車多, 3=壅塞, 4=阻塞
    let dataCollectTime: String?

    enum CodingKeys: String, CodingKey {
        case roadID = "RoadID"
        case roadName = "RoadName"
        case sectionID = "SectionID"
        case direction = "Direction"
        case speed = "Speed"
        case travelTime = "TravelTime"
        case congestionLevel = "CongestionLevel"
        case dataCollectTime = "DataCollectTime"
    }
}

struct TrafficIncident: Codable {
    let newsID: String?
    let title: String?
    let description: String?
    let startTime: String?
    let endTime: String?
    let roadName: String?
    let publishTime: String?

    enum CodingKeys: String, CodingKey {
        case newsID = "NewsID"
        case title = "Title"
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
    let locationName: LocalizedName?
    let videoStreamURL: String?
    let imageURL: String?
    let position: RailPosition?

    enum CodingKeys: String, CodingKey {
        case cctvID = "CCTVID"
        case roadID = "RoadID"
        case locationName = "LocationName"
        case videoStreamURL = "VideoStreamURL"
        case imageURL = "ImageURL"
        case position = "Position"
    }
}
