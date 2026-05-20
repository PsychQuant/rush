// Sources/CheTransportMCP/Models/MaritimeModels.swift
import Foundation

/// TDX maritime data is keyed by ferry operator (公司), not by city.
/// Common operators include "TWNC" (台馬輪), "OFR" (台灣航業) and several
/// regional ferry companies; consumers normally fetch the operator master
/// first then drill into routes/schedules.
struct MaritimeOperator: Codable {
    let operatorID: String
    let operatorName: LocalizedName?

    enum CodingKeys: String, CodingKey {
        case operatorID = "OperatorID"
        case operatorName = "OperatorName"
    }
}

struct MaritimeRoute: Codable {
    let routeID: String
    let routeName: LocalizedName?
    let operatorID: String?
    let departureStopID: String?
    let destinationStopID: String?
    let departureStopName: LocalizedName?
    let destinationStopName: LocalizedName?

    enum CodingKeys: String, CodingKey {
        case routeID = "RouteID"
        case routeName = "RouteName"
        case operatorID = "OperatorID"
        case departureStopID = "DepartureStopID"
        case destinationStopID = "DestinationStopID"
        case departureStopName = "DepartureStopName"
        case destinationStopName = "DestinationStopName"
    }
}
