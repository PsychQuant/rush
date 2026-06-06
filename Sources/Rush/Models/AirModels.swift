// Sources/Rush/Models/AirModels.swift
import Foundation

struct Airport: Codable {
    /// IATA code, e.g. "TPE", "TSA", "KHH".
    let airportID: String
    let airportName: LocalizedName
    let airportCityName: LocalizedName?

    enum CodingKeys: String, CodingKey {
        case airportID = "AirportID"
        case airportName = "AirportName"
        case airportCityName = "AirportCityName"
    }
}

struct FlightInfo: Codable {
    let flightNumber: String
    let airlineID: String?
    let departureAirportID: String?
    let arrivalAirportID: String?
    /// ISO-8601 string in TDX response.
    let scheduleDepartureTime: String?
    let scheduleArrivalTime: String?
    let actualDepartureTime: String?
    let actualArrivalTime: String?
    /// Status text (e.g. "On Time", "Delayed", "Boarding"). TDX FIDS returns
    /// these as plain strings, not a localized {Zh_tw,En} object.
    let departureRemark: String?
    let arrivalRemark: String?
    let terminal: String?
    let gate: String?
    let updateTime: String?

    enum CodingKeys: String, CodingKey {
        case flightNumber = "FlightNumber"
        case airlineID = "AirlineID"
        case departureAirportID = "DepartureAirportID"
        case arrivalAirportID = "ArrivalAirportID"
        case scheduleDepartureTime = "ScheduleDepartureTime"
        case scheduleArrivalTime = "ScheduleArrivalTime"
        case actualDepartureTime = "ActualDepartureTime"
        case actualArrivalTime = "ActualArrivalTime"
        case departureRemark = "DepartureRemark"
        case arrivalRemark = "ArrivalRemark"
        case terminal = "Terminal"
        case gate = "Gate"
        case updateTime = "UpdateTime"
    }
}
