// Sources/CheTransportMCP/Tools/AirTools.swift
import Foundation
import MCP

enum AirTools {
    static func defineTools() -> [Tool] {
        let directionEnum: Value = .array([.string("Arrival"), .string("Departure")])
        return [
            Tool(
                name: "air_list_airports",
                description: "列出台灣 TDX 收錄的所有機場（IATA code + 中英文名稱）。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "air_find_flights",
                description: "查指定機場某方向（到達／離開）的當日航班排程。可選 flight_number 精準查詢。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "airport": .object([
                            "type": .string("string"),
                            "description": .string("機場 IATA code，例如 TPE / TSA / KHH")
                        ]),
                        "direction": .object([
                            "type": .string("string"),
                            "description": .string("方向"),
                            "enum": directionEnum
                        ]),
                        "flight_number": .object([
                            "type": .string("string"),
                            "description": .string("（可選）航班號精準篩選")
                        ])
                    ]),
                    "required": .array([.string("airport"), .string("direction")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "air_status_flights",
                description: "查機場即時航班動態板（FIDS）— 含 actual 起降時間、登機門、狀態。即時資料不快取。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "airport": .object([
                            "type": .string("string"),
                            "description": .string("機場 IATA code")
                        ]),
                        "direction": .object([
                            "type": .string("string"),
                            "description": .string("方向"),
                            "enum": directionEnum
                        ])
                    ]),
                    "required": .array([.string("airport"), .string("direction")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            )
        ]
    }

    static func register(into registry: ToolRegistry, client: TDXClient, cache: Cache) async {
        await registry.register(tools: defineTools()) { name, args in
            await handleCall(name: name, arguments: args, client: client, cache: cache)
        }
    }

    static func handleCall(name: String, arguments: [String: Value], client: TDXClient, cache: Cache) async -> CallTool.Result {
        do {
            switch name {
            case "air_list_airports":
                return try await executeListAirports(client: client, cache: cache)
            case "air_find_flights":
                return try await executeFindFlights(arguments: arguments, client: client, cache: cache, live: false)
            case "air_status_flights":
                return try await executeFindFlights(arguments: arguments, client: client, cache: cache, live: true)
            default:
                return CallTool.Result(content: [.text(text: "Unknown air tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func executeListAirports(client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let data = try await client.fetch(
            path: TDXEndpoints.airAirport(),
            cacheTTL: 86400,
            cache: cache
        )
        let airports = decodeList(Airport.self, data: data)
        let payload = airports.map { airport -> [String: Any] in
            [
                "iata": airport.airportID,
                "name_zh": airport.airportName.zhTw ?? "",
                "name_en": airport.airportName.en ?? "",
                "city_zh": airport.airportCityName?.zhTw ?? "",
                "city_en": airport.airportCityName?.en ?? ""
            ]
        }
        return ToolResult.json(["airports": payload])
    }

    private static func executeFindFlights(arguments: [String: Value], client: TDXClient, cache: Cache, live: Bool) async throws -> CallTool.Result {
        let (airport, direction) = try parseAirportDirection(arguments)
        let path = TDXEndpoints.airFIDS(direction: direction, airport: airport)

        var queryItems: [URLQueryItem] = []
        if !live, let flightNumber = arguments["flight_number"]?.stringValue {
            queryItems.append(URLQueryItem(name: "$filter", value: "FlightNumber eq '\(flightNumber)'"))
        }

        let data = try await client.fetch(
            path: path,
            queryItems: queryItems,
            cacheTTL: live ? 0 : 600, // 10-min cache for non-live schedule lookups
            cache: cache
        )
        let flights = decodeList(FlightInfo.self, data: data)
        let payload = flights.map { flight -> [String: Any] in
            [
                "flight_no": flight.flightNumber,
                "airline": flight.airlineID ?? "",
                "from": flight.departureAirportID ?? "",
                "to": flight.arrivalAirportID ?? "",
                "schedule_dep": flight.scheduleDepartureTime ?? "",
                "schedule_arr": flight.scheduleArrivalTime ?? "",
                "actual_dep": flight.actualDepartureTime ?? "",
                "actual_arr": flight.actualArrivalTime ?? "",
                "status_dep": flight.departureRemark ?? "",
                "status_arr": flight.arrivalRemark ?? "",
                "terminal": flight.terminal ?? "",
                "gate": flight.gate ?? "",
                "updated_at": flight.updateTime ?? ""
            ]
        }
        return ToolResult.json([
            "airport": airport,
            "direction": direction,
            "flights": payload
        ])
    }

    // MARK: - Helpers

    static func parseAirportDirection(_ arguments: [String: Value]) throws -> (airport: String, direction: String) {
        guard let airport = arguments["airport"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: airport")
        }
        let normalized = airport.uppercased()
        guard normalized.count == 3, normalized.allSatisfy({ $0.isLetter }) else {
            throw TDXError.decoding("airport must be a 3-letter IATA code (got '\(airport)')")
        }
        guard let direction = arguments["direction"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: direction")
        }
        guard direction == "Arrival" || direction == "Departure" else {
            throw TDXError.decoding("direction must be 'Arrival' or 'Departure', got '\(direction)'")
        }
        return (normalized, direction)
    }

    static func decodeList<T: Codable>(_ type: T.Type, data: Data) -> [T] {
        (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }
}
