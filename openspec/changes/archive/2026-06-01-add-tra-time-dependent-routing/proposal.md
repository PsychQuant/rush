## Why

TRA 的 O/D 目前只有 `rail_find_trains`——列出某日從 A 到 B 的所有班次（raw passthrough，使用者自己讀時刻表）。它答不出真正的路由問題：「**現在**從台北到台中，考慮**即時誤點**，最早幾點到、搭哪班？」

這是 (B) 北極星的 **Stage 1**：一個 time-dependent、live-aware 的大眾運輸路由引擎（MCP-native、台灣深度，等同 OpenTripPlanner/RAPTOR 級別）。選 TRA 作為第一個模式，是因為它是**唯一同時擁有真實時刻表**（`DailyTrainTimetable` OD，含逐班 departure/arrival）**和逐車即時誤點**（`TrainLiveBoard` 的 DelayTime）的模式——能端到端證明「路徑隨即時狀況改變」這個 (B) 核心，而不必先解多模態與異質資料。

## What Changes

- 新增 MCP tool `rail_route(from, to, depart_after, system)`（system v1 僅 TRA）：在 TRA 真實時刻表上跑 **time-dependent earliest-arrival 路由**，套用 `TrainLiveBoard` 即時誤點平移班次時刻，回傳 **live-adjusted 最早抵達 itinerary**（搭哪班、幾點開、幾點到、是否受誤點影響）。
- 新增 connection 資料模型：從 `DailyTrainTimetable` OD 的 TrainInfo + StopTimes 抽出「班次連線」（沿用既有 `RailODFare` / `RailStopTime` 的 arrivalTime/departureTime）。
- 路由演算法：**time-expanded-graph Dijkstra**（earliest arrival）作為 v1 實作；之後再換成 CSA（Connection Scan Algorithm）。
- 即時調整：`TrainLiveBoard` 的 DelayTime 平移對應班次時刻，重新評估最早抵達。
- 新鮮度標註：itinerary 的時刻標明 `live`（已套用即時誤點）或 `scheduled`（無即時資料）。
- Graceful degradation：時刻表或即時資料不可用時，明確 surface（不 crash、不假裝），empty ≠ error。
- **不擴充 `rail_find_trains`**：它是「列班次」工具，與「算 itinerary」用途不同。
- Tool 總數 22 → 23。

## Non-Goals

- **多模態路由**（捷運/公車/跨運具）——headway 模式無逐班時刻表，屬 Stage 2/3。
- **CSA / RAPTOR**——v1 先用較好理解的 time-expanded Dijkstra，跑通後再換。
- **THSR**——雖有時刻表，但 TDX 無 THSR 即時車況板，做不了 live-adjustment；v1 限 TRA。
- 真實人行網路、door-to-door geocoding、票價最佳化。
- **不更動 `MetroGraph`**——捷運的 headway/2 靜態近似維持原樣，Stage 2 才併入 connection 引擎。

## Capabilities

### New Capabilities

- `tra-time-dependent-routing`: 在 TRA 真實時刻表上做 time-dependent earliest-arrival 路由，並以即時誤點調整、回傳 live-adjusted itinerary。

### Modified Capabilities

(none)

## Impact

- Affected specs: 新增 `tra-time-dependent-routing`
- Affected code:
  - New:
    - Sources/CheTransportMCP/Tools/TimetableRouter.swift
    - Tests/CheTransportMCPTests/TimetableRouterTests.swift
    - Tests/CheTransportMCPTests/Fixtures/tra_timetable_od.json
    - Tests/CheTransportMCPTests/Fixtures/tra_train_live_board.json
  - Modified:
    - Sources/CheTransportMCP/Models/RailModels.swift
    - Sources/CheTransportMCP/Tools/RailTools.swift
    - Sources/CheTransportMCP/Server.swift
    - Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift
    - CLAUDE.md
    - README.md
    - README_zh-TW.md
    - mcpb/manifest.json
  - Removed: （無）
