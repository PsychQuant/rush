// Sources/CheTransportMCP/Tools/TrafficTools.swift
import Foundation
import MCP

enum TrafficTools {
    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "traffic_freeway_live",
                description: "查全國／指定國道路段的即時車速、車流量與壅塞等級。即時資料不快取。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "road_id": .object([
                            "type": .string("string"),
                            "description": .string("（可選）國道編號，如「000010」=國道1號；不指定回全國")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "traffic_incidents",
                description: "查最新道路施工、封閉、事故與其他交通公告。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "keyword": .object([
                            "type": .string("string"),
                            "description": .string("（可選）關鍵字過濾標題與描述")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: true)
            ),
            Tool(
                name: "traffic_cctv",
                description: "取得國道／省道 CCTV 即時影像串流網址。可依 road_id 過濾。",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "road_id": .object([
                            "type": .string("string"),
                            "description": .string("（可選）道路 ID 過濾")
                        ])
                    ]),
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
            case "traffic_freeway_live":
                return try await executeFreewayLive(arguments: arguments, client: client, cache: cache)
            case "traffic_incidents":
                return try await executeIncidents(arguments: arguments, client: client, cache: cache)
            case "traffic_cctv":
                return try await executeCCTV(arguments: arguments, client: client, cache: cache)
            default:
                return CallTool.Result(content: [.text(text: "Unknown traffic tool: \(name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error in \(name): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func executeFreewayLive(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        var queryItems: [URLQueryItem] = []
        if let roadID = arguments["road_id"]?.stringValue, !roadID.isEmpty {
            queryItems.append(URLQueryItem(name: "$filter", value: "RoadID eq '\(roadID)'"))
        }
        let data = try await client.fetch(
            path: TDXEndpoints.trafficFreewayLive(),
            queryItems: queryItems,
            cacheTTL: 0,
            cache: cache
        )
        let entries = TDXDecode.list(FreewayLive.self, from: data)
        let payload = entries.map { entry -> [String: Any] in
            [
                "section_id": entry.sectionID ?? "",
                "travel_time_s": entry.travelTime ?? -1,
                "speed_kmh": entry.travelSpeed ?? -1,
                "congestion_level": entry.congestionLevelID ?? "",
                "congestion_text": entry.congestionLevel ?? "",
                "collected_at": entry.dataCollectTime ?? ""
            ]
        }
        return ToolResult.json(["entries": payload, "count": payload.count])
    }

    private static func executeIncidents(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        let data = try await client.fetch(
            path: TDXEndpoints.trafficNews(),
            cacheTTL: 300, // 5 min — news cycle slower than freeway live
            cache: cache
        )
        let incidents = TDXDecode.list(TrafficIncident.self, from: data)
        let keyword = arguments["keyword"]?.stringValue?.lowercased() ?? ""
        let filtered = keyword.isEmpty ? incidents : incidents.filter { incident in
            let hay = [incident.title, incident.description, incident.roadName]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return hay.contains(keyword)
        }
        let payload = filtered.map { incident -> [String: Any] in
            [
                "news_id": incident.newsID ?? "",
                "title": incident.title ?? "",
                "url": incident.newsURL ?? "",
                "description": incident.description ?? "",
                "road_name": incident.roadName ?? "",
                "start_time": incident.startTime ?? "",
                "end_time": incident.endTime ?? "",
                "published_at": incident.publishTime ?? ""
            ]
        }
        return ToolResult.json(["incidents": payload, "count": payload.count])
    }

    private static func executeCCTV(arguments: [String: Value], client: TDXClient, cache: Cache) async throws -> CallTool.Result {
        var queryItems: [URLQueryItem] = []
        if let roadID = arguments["road_id"]?.stringValue, !roadID.isEmpty {
            queryItems.append(URLQueryItem(name: "$filter", value: "RoadID eq '\(roadID)'"))
        }
        let data = try await client.fetch(
            path: TDXEndpoints.trafficCCTVHighway(),
            queryItems: queryItems,
            cacheTTL: 86400, // CCTV inventory rarely changes
            cache: cache
        )
        let cctvs = TDXDecode.list(TrafficCCTV.self, from: data)
        let payload = cctvs.map { cctv -> [String: Any] in
            var dict: [String: Any] = [
                "cctv_id": cctv.cctvID,
                "road_id": cctv.roadID ?? "",
                "road_name": cctv.roadName ?? "",
                "location": cctv.surveillanceDescription ?? "",
                "video_url": cctv.videoStreamURL ?? "",
                "image_url": cctv.videoImageURL ?? ""
            ]
            if let lat = cctv.positionLat, let lon = cctv.positionLon {
                dict["lat"] = lat
                dict["lon"] = lon
            }
            return dict
        }
        return ToolResult.json(["cctvs": payload, "count": payload.count])
    }
}
