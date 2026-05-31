## Why

che-transport-mcp 對捷運（TRTC/TYMC/KRTC/TMRT/NTDLRT/KLRT）目前只有 `rail_search_stations`（站點搜尋）與 `rail_status_station`（即時站牌板），**沒有 O/D 路線查詢**。使用者問「臺北車站→南港」這類捷運點對點，工具答不出來（`rail_find_trains` 的 system enum 只有 TRA/THSR）。捷運是雙北最高頻運具，這是核心查詢缺口。見 PsychQuant/che-transport-mcp#5。

實測 TDX 捷運四個端點皆可用（200），data model 清楚，可支撐 O/D 直達查詢。

## What Changes

- 新增 MCP tool `metro_find_route(from, to, system)`：查捷運**直達** O/D，回傳連接線（line）+ 站到站旅行時間 + 當下時段班距。
- 新增 `Sources/CheTransportMCP/Tools/MetroTools.swift`（tool 定義 + dispatch + 直達路由邏輯）與 `Sources/CheTransportMCP/Models/MetroModels.swift`（StationOfRoute / S2STravelTime / Frequency / Line 的 Codable model）。
- 在 `TDXEndpoints` registry 新增 4 個 metro 端點 builder（`v2/Rail/Metro/{StationOfRoute,S2STravelTime,Frequency,Line}/{op}`）+ 對應 contract cases，自動納入 nightly 驗證。
- 在 Server 註冊新 tool；tool 總數 21 → 22。
- **BREAKING**：無——純增量。

## Non-Goals

- **轉乘路線規劃**（跨線換乘）— 切到 PsychQuant/che-transport-mcp#6，本 change 只做單一 route 直達。
- 跨運具（捷運+公車+台鐵）整合路徑規劃。
- 即時到站班次配對（屬 `rail_status_station` 範疇，非 O/D 規劃）。
- 擴充 `rail_find_trains` 接受捷運（被否決：捷運按班距營運、回傳形狀與 TRA train list 不同，混用會讓 schema 語意分裂）。

## Capabilities

### New Capabilities

- `metro-od-routing`: 捷運直達 O/D 路線查詢——給起訖站 + 系統，回連接線、站到站旅行時間、當下時段班距。

### Modified Capabilities

(none)

## Impact

- Affected specs: 新增 `metro-od-routing`
- Affected code:
  - New:
    - Sources/CheTransportMCP/Tools/MetroTools.swift
    - Sources/CheTransportMCP/Models/MetroModels.swift
    - Tests/CheTransportMCPTests/MetroToolsTests.swift
  - Modified:
    - Sources/CheTransportMCP/TDXEndpoints.swift
    - Sources/CheTransportMCP/Server.swift
    - Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift
    - CLAUDE.md
    - README.md
    - README_zh-TW.md
    - mcpb/manifest.json
  - Removed: （無）
