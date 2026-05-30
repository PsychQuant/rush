// Sources/CheTransportMCP/Tools/BikeTools.swift
import Foundation
import MCP

enum BikeTools {
    // MARK: - Tool definitions

    static func defineTools() -> [Tool] {
        let cityEnum: Value = .array(BikeCity.allCases.map { .string($0.rawValue) })
        let serviceTypeEnum: Value = .array([.string("YouBike1.0"), .string("YouBike2.0")])
        return [
            Tool(
                name: "bike_search_stations",
                description: "依名稱模糊搜尋 YouBike 站點。city 必填；service_type 可選（YouBike1.0 / YouBike2.0），不指定回兩種。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("站名關鍵字（支援臺/台互換）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ]),
                        "service_type": .object([
                            "type": .string("string"),
                            "description": .string("YouBike 版本（可選）"),
                            "enum": serviceTypeEnum
                        ])
                    ]),
                    "required": .array([.string("query"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bike_stations_nearby",
                description: "找指定座標附近的 YouBike 站點 + 即時可借/可還車數。回傳依距離排序。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "lat": .object([
                            "type": .string("number"),
                            "description": .string("緯度，WGS84")
                        ]),
                        "lon": .object([
                            "type": .string("number"),
                            "description": .string("經度，WGS84")
                        ]),
                        "radius_m": .object([
                            "type": .string("integer"),
                            "description": .string("搜尋半徑（公尺，預設 500，最大 3000）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("lat"), .string("lon"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "bike_status_station",
                description: "查單一站點即時可借/可還車數。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "station_id": .object([
                            "type": .string("string"),
                            "description": .string("站點 StationUID（用 bike_search_stations 取得）")
                        ]),
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ])
                    ]),
                    "required": .array([.string("station_id"), .string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            )
        ]
    }

    // MARK: - Registry registration

    static func register(into registry: ToolRegistry, client: TDXClient, cache: Cache) async {
        await registry.register(tools: defineTools()) { name, args in
            await handleCall(name: name, arguments: args, client: client, cache: cache)
        }
    }

    static func handleCall(name: String, arguments: [String: Value], client: TDXClient, cache: Cache) async -> CallTool.Result {
        do {
            switch name {
            case "bike_search_stations":
                return try await executeSearchStations(arguments: arguments, client: client, cache: cache)
            case "bike_stations_nearby":
                return try await executeStationsNearby(arguments: arguments, client: client, cache: cache)
            case "bike_status_station":
                return try await executeStatusStation(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown bike tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - Executors

    private static func executeSearchStations(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let query = arguments["query"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: query")
        }
        let city = try parseCity(arguments)
        let serviceType = parseServiceType(arguments["service_type"]?.stringValue)

        let data = try await client.fetch(
            path: TDXEndpoints.bikeStation(city.rawValue),
            cacheTTL: 86400,
            cache: cache
        )
        let stations = decodeList(BikeStation.self, data: data)
        let filtered = stations.filter { station in
            if let st = serviceType, station.serviceType != st.rawValue { return false }
            return matchesName(query: query, name: station.stationName)
        }
        let matches = filtered.map { station -> [String: Any] in
            var dict: [String: Any] = [
                "station_uid": station.stationUID,
                "station_id": station.stationID ?? "",
                "name_zh": station.stationName.zhTw ?? "",
                "name_en": station.stationName.en ?? "",
                "service_type": station.serviceType ?? 0,
                "capacity": station.bikesCapacity ?? -1
            ]
            if let pos = station.stationPosition {
                dict["lat"] = pos.positionLat
                dict["lon"] = pos.positionLon
            }
            return dict
        }
        return jsonResult(["matches": matches, "city": city.rawValue])
    }

    private static func executeStationsNearby(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let lat = arguments["lat"]?.doubleValue else {
            throw TDXError.decoding("Missing required parameter: lat")
        }
        guard let lon = arguments["lon"]?.doubleValue else {
            throw TDXError.decoding("Missing required parameter: lon")
        }
        let radiusM = arguments["radius_m"]?.intValue ?? 500
        let clamped = max(50, min(radiusM, 3000))
        let city = try parseCity(arguments)

        let stationData = try await client.fetch(
            path: TDXEndpoints.bikeStation(city.rawValue),
            cacheTTL: 86400,
            cache: cache
        )
        let availData = try await client.fetch(
            path: TDXEndpoints.bikeAvailability(city.rawValue),
            cacheTTL: 0,
            cache: cache
        )
        let stations = decodeList(BikeStation.self, data: stationData)
        let availability = decodeList(BikeAvailability.self, data: availData)
        let availByUID = Dictionary(uniqueKeysWithValues: availability.map { ($0.stationUID, $0) })

        let withDistance: [(BikeStation, BikeAvailability?, Double)] = stations.compactMap { station in
            guard let pos = station.stationPosition else { return nil }
            let dist = haversine(lat1: lat, lon1: lon, lat2: pos.positionLat, lon2: pos.positionLon)
            guard dist <= Double(clamped) else { return nil }
            return (station, availByUID[station.stationUID], dist)
        }.sorted { $0.2 < $1.2 }

        let payload = withDistance.map { tuple -> [String: Any] in
            let (station, avail, dist) = tuple
            var dict: [String: Any] = [
                "station_uid": station.stationUID,
                "name_zh": station.stationName.zhTw ?? "",
                "service_type": station.serviceType ?? 0,
                "distance_m": Int(dist.rounded()),
                "available_rent": avail?.availableRentBikes ?? -1,
                "available_return": avail?.availableReturnBikes ?? -1,
                "service_status": avail?.serviceStatus ?? 0
            ]
            if let pos = station.stationPosition {
                dict["lat"] = pos.positionLat
                dict["lon"] = pos.positionLon
            }
            return dict
        }
        return jsonResult([
            "matches": payload,
            "city": city.rawValue,
            "center": ["lat": lat, "lon": lon],
            "radius_m": clamped
        ])
    }

    private static func executeStatusStation(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        guard let stationID = arguments["station_id"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: station_id")
        }
        let city = try parseCity(arguments)

        let data = try await client.fetch(
            path: TDXEndpoints.bikeAvailability(city.rawValue),
            queryItems: [URLQueryItem(name: "$filter", value: "StationUID eq '\(stationID)'")],
            cacheTTL: 0,
            cache: cache
        )
        let availability = decodeList(BikeAvailability.self, data: data)
        guard let avail = availability.first else {
            return jsonResult(["station_id": stationID, "city": city.rawValue, "found": false])
        }
        return jsonResult([
            "station_id": stationID,
            "city": city.rawValue,
            "found": true,
            "available_rent": avail.availableRentBikes ?? -1,
            "available_return": avail.availableReturnBikes ?? -1,
            "service_status": avail.serviceStatus ?? 0
        ])
    }

    // MARK: - Helpers

    static func parseCity(_ arguments: [String: Value]) throws -> BikeCity {
        guard let cityRaw = arguments["city"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: city")
        }
        guard let city = BikeCity(rawValue: cityRaw) else {
            let valid = BikeCity.allCases.map(\.rawValue).joined(separator: ", ")
            throw TDXError.decoding("Invalid city '\(cityRaw)'. Valid: \(valid)")
        }
        return city
    }

    static func parseServiceType(_ raw: String?) -> BikeServiceType? {
        switch raw {
        case "YouBike1.0": return .youBike1_0
        case "YouBike2.0": return .youBike2_0
        default: return nil
        }
    }

    static func matchesName(query: String, name: LocalizedName) -> Bool {
        let normalized = query.replacingOccurrences(of: "台", with: "臺").lowercased()
        let zh = (name.zhTw ?? "").replacingOccurrences(of: "台", with: "臺").lowercased()
        let en = (name.en ?? "").lowercased()
        return zh.contains(normalized) || en.contains(normalized)
    }

    /// Great-circle distance in metres. Mean Earth radius = 6,371 km.
    static func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
              + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }

    static func decodeList<T: Codable>(_ type: T.Type, data: Data) -> [T] {
        (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    static func jsonResult(_ obj: [String: Any]) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: JSONSanitize.clean(obj))) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}
