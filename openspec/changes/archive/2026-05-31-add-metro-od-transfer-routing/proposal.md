## Why

#5 的 `metro_find_route` v1 只做**直達**（單一 route 的 Stations 同時含 from+to）。起訖兩站不在同一條線時回空 + 轉乘提示，無法規劃跨線行程——而雙北最常見的捷運 O/D（如台北車站→淡水、板橋→南港需經換乘）正是跨線。

diagnose 實測確認 TDX `v2/Rail/Metro/LineTransfer/{op}` 可用（TRTC 34 筆、KRTC 2 筆轉乘關係），且 `TransferTime`（月台間步行分鐘）為現成欄位、`LineTransfer` 的每一筆正好橋接「同一實體站跨線不同 StationID」（板橋 = 板南線 BL07 / 環狀線 Y16）。把捷運站網建成圖跑最短路徑即可支援轉乘。見 PsychQuant/che-transport-mcp#6。

## What Changes

- **擴充既有 tool `metro_find_route`（不新增 tool）**：跨線 O/D 回傳轉乘路徑。輸出 restructure 為 `routes[].legs[]`（每段一條線）+ `transfers[]`（每個換乘點）+ `transfer_count` + 總 `travel_time_min`。直達 = 1 leg / 0 transfer，與轉乘同一形狀。此為對 v0.4.0 直達輸出（flat 形狀）的演進。
- **一律建圖跑最短路徑**，取代 #5 的 direct short-circuit gate：node = 站、edge = 同線相鄰站（`S2STravelTime` 的 RunTime+StopTime 為權重）+ 轉乘邊（`LineTransfer` 的 `TransferTime` 為權重）。直達自然落為 0-transfer 最短路徑，並能抓到環狀線比長程直達更快的情況。
- **轉乘成本** = `LineTransfer.TransferTime`（步行，hard data）+ `headway/2`（等下一班車，標註為估計），每個換乘點各別 surface（`walk_min` / `wait_min`）。
- **「最佳」= 總時間最短**（Dijkstra），回 ≤3 候選；若最少轉乘路徑與最短時間路徑不同則一併列出。各候選含 `travel_time_min` + `transfer_count`，依時間升冪。
- **新 data surface**：`TDXEndpoints.metroLineTransfer(op)` builder + `MetroLineTransfer` Codable model + 一個代表系統（TRTC）contract case（registry contract 26→31）。
- 擴充既有 `metro-od-routing` spec（#5 promoted）的 routing requirement，並把 LineTransfer 納入 registry requirement。
- Tool 總數不變（仍 22）——擴充既有 tool 而非新增。

## Non-Goals

- **跨運具轉乘**（捷運+公車+台鐵）——仍限單一捷運系統內。
- **即時班次配對**——仍是規劃層，`wait_min` 為 headway/2 估計，非真實到站時刻。
- **新增獨立 tool**（如 metro_find_transfer_route）——已否決：使用者問 A→B 的方式不該依「是否直達」而分裂成兩個 tool；直達是 transfer_count=0 的最短路徑，同一輸出形狀。
- **預建/常駐 graph 快取**——graph on-demand 建構，靠既有 TDXClient 24h dataset cache；不另設 graph cache（YAGNI）。
- **國定假日 service-day 偵測**——沿用 #5 的 weekday-only headway 選擇。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `metro-od-routing`: 從「僅直達 O/D」擴充為「直達 + 跨線轉乘」的最短路徑規劃；輸出形狀改為 legs/transfers；LineTransfer 端點納入 registry。

## Impact

- Affected specs: `metro-od-routing`（modified）
- Affected code:
  - New:
    - Sources/CheTransportMCP/Tools/MetroGraph.swift
    - Tests/CheTransportMCPTests/MetroGraphTests.swift
    - Tests/CheTransportMCPTests/Fixtures/metro_line_transfer.json
  - Modified:
    - Sources/CheTransportMCP/Models/MetroModels.swift
    - Sources/CheTransportMCP/TDXEndpoints.swift
    - Sources/CheTransportMCP/Tools/MetroTools.swift
    - Tests/CheTransportMCPTests/MetroModelsTests.swift
    - Tests/CheTransportMCPTests/MetroToolsTests.swift
    - Tests/CheTransportMCPTests/TDXEndpointsTests.swift
    - CLAUDE.md
    - README.md
    - README_zh-TW.md
    - mcpb/manifest.json
  - Removed: （無）
