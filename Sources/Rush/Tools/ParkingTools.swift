// Sources/Rush/Tools/ParkingTools.swift
import Foundation
import MCP

enum ParkingTools {
    static func defineTools() -> [Tool] {
        let cityEnum: Value = .array(ParkingCity.allCases.map { .string($0.rawValue) })
        return [
            Tool(
                name: "parking_list_lots",
                description: "列出指定城市的路外（off-street）停車場名單。回傳含位置與總車位數；coverage 集中在六都與主要縣市。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ]),
                        "keyword": .object([
                            "type": .string("string"),
                            "description": .string("（可選）停車場名稱或地址關鍵字過濾")
                        ])
                    ]),
                    "required": .array([.string("city")]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "parking_status",
                description: "查某城市停車場即時剩餘車位數。可選 lot_id 鎖定單一停車場。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("城市代碼"),
                            "enum": cityEnum
                        ]),
                        "lot_id": .object([
                            "type": .string("string"),
                            "description": .string("（可選）停車場 CarParkID")
                        ])
                    ]),
                    "required": .array([.string("city")]),
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
            case "parking_list_lots":
                return try await executeListLots(arguments: arguments, client: client, cache: cache)
            case "parking_status":
                return try await executeStatus(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown parking tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func executeListLots(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let city = try parseCity(arguments)
        let data = try await client.fetch(
            path: TDXEndpoints.parkingCarPark(city.rawValue),
            cacheTTL: 86400,
            cache: cache
        )
        let lots = TDXDecode.list(ParkingLot.self, from: data)
        let keyword = arguments["keyword"]?.stringValue?.lowercased() ?? ""
        let filtered = keyword.isEmpty ? lots : lots.filter { lot in
            let hay = [lot.carParkName?.zhTw, lot.carParkName?.en, lot.address]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return hay.contains(keyword)
        }
        let payload = filtered.map { lot -> [String: Any] in
            var dict: [String: Any] = [
                "lot_id": lot.carParkID,
                "name_zh": lot.carParkName?.zhTw ?? "",
                "name_en": lot.carParkName?.en ?? "",
                "address": lot.address ?? "",
                "total_spaces": lot.totalSpaces ?? -1,
                "type": lot.carParkType ?? 0
            ]
            if let pos = lot.carParkPosition {
                dict["lat"] = pos.positionLat
                dict["lon"] = pos.positionLon
            }
            return dict
        }
        return ToolResult.json(["lots": payload, "city": city.rawValue, "count": payload.count])
    }

    private static func executeStatus(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let city = try parseCity(arguments)
        var queryItems: [URLQueryItem] = []
        if let lotID = arguments["lot_id"]?.stringValue, !lotID.isEmpty {
            queryItems.append(URLQueryItem(name: "$filter", value: "CarParkID eq '\(lotID)'"))
        }
        let data = try await client.fetch(
            path: TDXEndpoints.parkingAvailability(city.rawValue),
            queryItems: queryItems,
            cacheTTL: 0,
            cache: cache
        )
        let entries = TDXDecode.list(ParkingAvailability.self, from: data)
        let payload = entries.map { entry -> [String: Any] in
            [
                "lot_id": entry.carParkID,
                "available": entry.availableSpaces ?? -1,
                "service_status": entry.serviceStatus ?? 0,
                "collected_at": entry.dataCollectTime ?? ""
            ]
        }
        return ToolResult.json(["entries": payload, "city": city.rawValue, "count": payload.count])
    }

    static func parseCity(_ arguments: [String: Value]) throws -> ParkingCity {
        guard let cityRaw = arguments["city"]?.stringValue else {
            throw TDXError.decoding("Missing required parameter: city")
        }
        guard let city = ParkingCity(rawValue: cityRaw) else {
            let valid = ParkingCity.allCases.map(\.rawValue).joined(separator: ", ")
            throw TDXError.decoding("Invalid city '\(cityRaw)'. Valid: \(valid)")
        }
        return city
    }
}
