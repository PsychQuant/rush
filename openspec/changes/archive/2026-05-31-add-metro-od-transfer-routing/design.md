## Context

#5 的 `metro_find_route` 只做直達（StationOfRoute 找單一 route 同時含 from+to，gate 短路：有直達就回、跳過其他 fetch）。跨線 O/D 回空 + 轉乘提示。#6 要支援跨線轉乘。

diagnose 實測（`v2/Rail/Metro/LineTransfer/{op}`）：TRTC 34 筆、KRTC 2 筆轉乘關係；TYMC 空；TMRT/NTDLRT/KLRT HTTP 400（單線系統）。`LineTransfer` 每筆含 FromLine/FromStation → ToLine/ToStation、`IsOnSiteTransfer`、`TransferTime`（步行分鐘，現成）。這正好橋接「同一實體站跨線不同 StationID」（板橋 BL07/Y16）。

既有基礎（#5）：`MetroStationOfRoute`（站序列）、`MetroS2STravelTime`（相鄰站 RunTime+StopTime）、`MetroFrequency`（headway，已有當下時段選擇）、`MetroLine`（線名/色）皆在 registry + model。`MetroTools.travelTimeMinutes` 已做方向無關的相鄰站 lookup（S2S 單向儲存的對稱處理）。

## Goals / Non-Goals

**Goals:**

- `metro_find_route` 支援單一捷運系統內的跨線轉乘 O/D，回連接路徑（每段線）+ 各換乘點 + 總時間。
- 直達與轉乘統一為「最短路徑」概念，單一輸出形狀。
- LineTransfer 納入 registry 單一事實來源 + contract case。
- 單線/無轉乘系統 graceful（empty ≠ error）。

**Non-Goals:**

- 跨運具轉乘、即時班次配對、新增獨立 tool、graph 常駐快取、國定假日偵測。

## Decisions

### 擴充 metro_find_route，輸出統一為 legs

不新增 tool。`metro_find_route(from, to, system)` 輸入不變；輸出 restructure 為 `routes[]`，每筆 `{ legs[], transfers[], transfer_count, travel_time_min }`。`legs[]` 每段 `{ line_id, line_name, line_color, from_station_id, from_name, to_station_id, to_name, travel_time_min, headway_min, headway_max_min }`；`transfers[]` 每換乘 `{ station_id, station_name, from_line, to_line, walk_min, wait_min }`。直達 = 1 leg / 0 transfer / 空 transfers。此演進 v0.4.0 的 flat 直達輸出（v0.4.0 僅一日、無鎖定 consumer，可接受）。

理由：使用者問 A→B 不該依「是否直達」分裂成兩個 tool；直達是 transfer_count=0 的最短路徑，同一形狀。替代方案（新 tool metro_find_transfer_route）否決——兩個 tool 答同一問題。

### 一律建圖跑最短路徑（取代 #5 gate）

移除 #5 的 direct short-circuit。一律建圖：node = (system 內所有) 站；edge = 同線相鄰站（雙向，權重 = S2S RunTime + 中間站 StopTime，沿用 #5 方向無關 lookup）+ 轉乘邊（雙向，權重 = LineTransfer TransferTime + 目的線 headway/2 估計）。對 from→to 跑 Dijkstra by time。直達自然落為 0-transfer 最短路徑，且能抓到環狀線比長程直達更快的情況。

理由：直達/轉乘合為一條 code path（消除 special-case）+ 正確性（環狀捷徑）。代價：直達 query cold-cache 由 1 fetch 變 5 fetch，但 dataset 24h cache 使其為 once/day/system 的攤提成本。替代方案（保留 gate + 僅無直達時建圖）否決——兩條 code path 且漏環狀捷徑。

### 轉乘成本 = TransferTime（步行）+ headway/2（等車，估計）

轉乘邊權重 = `TransferTime`（hard data）+ 目的線當下時段 `headway/2`（估計）。輸出的 `transfers[]` 各別 surface `walk_min`（TransferTime）與 `wait_min`（headway/2，標為估計）。

理由：步行時間現成，等車是 expected-wait 標準模型且 #5 已能算當下 headway。替代方案（只回步行）否決——低估總時間。

### 最佳 = 最短時間，回 ≤3 候選 + 最少轉乘

主結果 = Dijkstra by total time 的最短路徑。另算最少轉乘路徑；若與最短時間路徑不同則一併列入。回 routes[]（≤3），依 travel_time_min 升冪，各含 transfer_count 供 caller 取捨。

理由：時間 vs 轉乘數是真實取捨；小候選集 + transfer_count 讓 caller 選，不在工具端武斷。

### MetroGraph 為內部 helper（新檔，同 module），on-demand 建構

graph 建構 + Dijkstra 放新檔 `Sources/CheTransportMCP/Tools/MetroGraph.swift`（同 target 內部 helper，非新 module/外部 seam；分檔僅因 MetroTools.swift 已近 300 行）。每次查詢即時建圖，4 個 dataset（StationOfRoute/S2STravelTime/Frequency/Line/LineTransfer）經既有 TDXClient 24h cache。不設常駐 graph 快取。

理由：圖規模小（TRTC ~100+ 站），Dijkstra 微秒級；dataset cache 已涵蓋 fetch 成本。

### LineTransfer 進 registry + 單線系統 graceful

`TDXEndpoints.metroLineTransfer(op)` = `v2/Rail/Metro/LineTransfer/{op}`（沿用 dataset-before-operator 慣例）+ `MetroLineTransfer` Codable model + 一個代表系統（TRTC）contract case（contract 26→31）。production 經 registry 取路徑，無 inline 字面值。單線系統 LineTransfer HTTP 400 / 空：以 `try?` 容錯解為空轉乘集 → graph 無轉乘邊 → 回直達路徑或空 + note，不 error。

## Implementation Contract

- **Behavior**：`metro_find_route(from, to, system)` 建單一捷運系統站網圖跑最短路徑，回 `routes[]`（≤3，依總時間升冪），每筆含 `legs[]`（每段一線 + 該段時間/班距）、`transfers[]`（每換乘站 + walk_min + wait_min）、`transfer_count`、總 `travel_time_min`。直達 = 1 leg / 0 transfer。兩站不連通（或單線系統無對應）→ 空 `routes` + `note`（empty ≠ error）。
- **Interface / data shape**：輸入不變（`from` StationID、`to` StationID、`system` 6 個 metro 代碼之一）。輸出形狀如上（restructure 自 v0.4.0 的 flat 直達形狀）。
- **Failure modes**：invalid system / 缺參數 → decoding error；不可達 → 空 routes + note（非 error）；LineTransfer HTTP 400 或空（單線系統）→ 容錯為無轉乘邊，回直達或空；TDX network / rate-limit → 沿用 TDXClient surface。
- **Acceptance criteria**：
  1. `metro_find_route(臺北車站 → 淡水, TRTC)` 回經換乘的路徑（transfer_count ≥ 1），各換乘含 walk_min + wait_min，總 travel_time_min 為各 leg + 各換乘成本之和。
  2. 直達 regression：`metro_find_route(臺北車站 BL12 → 南港 BL22, TRTC)` 仍回 0-transfer、板南線、travel_time 與 #5 一致量級。
  3. `TDXEndpoints.metroLineTransfer` + contract case 進 registry，`TDX_CONTRACT=1` 下含 LineTransfer 端點綠；contract case 數更新並斷言（26→31）。
  4. 離線 `swift test` 全綠不需網路，含 MetroGraph 單元測試（Dijkstra 最短路徑、環狀捷徑勝過長程直達、單線系統無轉乘邊 graceful、不可達回空）。
  5. tool 總數仍 22（擴充既有 tool，未新增）；MCPJSONRPCSmokeTest 綠。
  6. grep production 無 registry 以外的 metro 路徑字面值。
- **Scope boundaries**：in scope = 單一捷運系統內直達 + 轉乘最短路徑、LineTransfer registry/model/contract、MetroGraph helper、輸出 restructure、docs。out of scope = 跨運具轉乘、即時班次配對、新 tool、graph 常駐快取、國定假日偵測。

## Risks / Trade-offs

- **輸出 restructure 改 v0.4.0 形狀**：v0.4.0 僅一日、無鎖定 consumer → 可接受；CHANGELOG 標明形狀演進。
- **環狀線雙向 + S2S 單向儲存**：graph 相鄰邊需方向無關（沿用 #5 對稱 lookup），雙向加邊。
- **多候選去重**：同一最短路徑可能有等價表述；以 (路線序列 + 換乘站序列) 為 key 去重。
- **headway/2 估計噪音**：wait_min 標為估計，walk_min 為 hard data，分開呈現。
- **跨 system 不連通**：只在單一 system 內建圖；不同 system 的站不連（符合 single-system scope）。
- **LineTransfer 資料新鮮度（UpdateTime 2020）**：站網變動低可接受；新線/新站開通由 contract test 揭露。
