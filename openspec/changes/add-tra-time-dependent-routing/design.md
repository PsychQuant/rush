## Context

`rail_find_trains` 用 `TDXEndpoints.railTimetableOD`（`DailyTrainTimetable` OD）列出某日 A→B 的班次，raw passthrough。既有 model `RailODFare`（trainInfo + stopTimes）與 `RailStopTime`（含 `arrivalTime` / `departureTime`）已能描述「每班車在 from/to 的時刻」。即時誤點端點 `TDXEndpoints.railTrainLiveBoard`（`TrainLiveBoard`，逐車 `DelayTime`）也已在 registry，`RailLiveTrain` 已 model（trainNo / delayTime）。

這是 (B) 北極星的 Stage 1。北極星 = time-dependent、live-aware、多模態路由引擎（MCP-native、台灣深度，CSA/RAPTOR 級）。Stage 1 只做 TRA，因為它是唯一同時有真實時刻表 + 逐車即時誤點的模式。

**異質資料約束（北極星層級）**：TDX 中 TRA/THSR 是時刻表模式（離散班次連線），捷運/公車是 headway 模式（無逐班時刻表）。統一多模態 connection 引擎是 Stage 2/3，本 change 不碰；既有 `MetroGraph`（headway/2 靜態 Dijkstra）維持為捷運靜態近似。

## Goals / Non-Goals

**Goals:**

- 新 tool 在 TRA 時刻表上做 time-dependent earliest-arrival 路由。
- 套用即時誤點 → 回 live-adjusted 最早抵達 itinerary，且路徑會因誤點改變。
- 時刻標明 live / scheduled；資料缺失 graceful。

**Non-Goals:**

- 多模態、捷運/公車（headway 模式，Stage 2/3）。
- 全網（非 OD）跨車轉乘——需抓完整每日時刻表，本 change 只用 OD 端點回傳的班次。
- CSA/RAPTOR（v1 先 time-expanded Dijkstra）；THSR（無即時車況板）；票價；door-to-door。
- 不更動 `MetroGraph`。

## Decisions

### 新 tool `rail_route`，不擴充 `rail_find_trains`

`rail_route(from, to, depart_after?, system)`（system enum v1 僅 `TRA`；`depart_after` 預設 now Asia/Taipei，格式 `HH:mm`）。輸出 itinerary（搭哪班、開/到時刻、是否受誤點影響），與 `rail_find_trains` 的「列班次」用途不同——後者 raw passthrough 班次清單，前者算最佳 itinerary。否決擴充 rail_find_trains：output 語意分裂。Tool 數 22 → 23。

### Connection 模型沿用 RailODFare / RailStopTime

`DailyTrainTimetable` OD 回傳的每班車含 StopTimes（含 from、to 的 departure/arrival `HH:mm`）。沿用既有 `RailODFare` / `RailStopTime`（已有 arrivalTime/departureTime）解析；不新增 model。每班車在區間內的相鄰停靠 = 時間戳連線。

### time-expanded earliest-arrival Dijkstra（CSA 之後再換）

建 time-expanded 圖：node = (站, 時刻) 事件；edge = 同班車相鄰停靠的 ride 邊（依時刻）+ 同站候車邊。從 (from, depart_after) 跑 earliest-arrival Dijkstra（cost = 抵達時刻）。對「OD 直達班次」此圖退化為「在 depart_after 後出發、抵達最早的那班」；若 OD 回傳的班次在中間站可接續，圖自然找到接續 itinerary。全網（非 OD 班次）轉乘需完整時刻表 → 本 change 範圍外。理由：time-expanded Dijkstra 直接複用既有 Dijkstra 心智模型、好驗證；CSA 是後續效能升級。

### 即時誤點調整：TrainLiveBoard DelayTime 平移班次時刻

查 `TrainLiveBoard`（全 TRA，client 端用 `RailLiveTrain.trainNo` 對應）取每班 `DelayTime`（分）。建圖時把該班車所有時刻 + DelayTime。對誤點班次平移後重算 earliest-arrival → 選出的 itinerary 因即時誤點而改變（例：表訂最早的車誤點 12 分，較晚的準點車反而先到 → 回後者）。

### 新鮮度標註 + graceful degradation

itinerary 每筆標 `source: live`（已套用對應 DelayTime）或 `scheduled`（該班無即時資料）。`TrainLiveBoard` 不可用 → 全 scheduled + note；`DailyTrainTimetable` OD 不可用（見 Risk）→ 回空 + note（非 crash）。empty ≠ error。

## Implementation Contract

- **Behavior**：`rail_route(from, to, depart_after, system=TRA)` 抓 OD 時刻表（連線）+ TrainLiveBoard（誤點），建 time-expanded 圖，從 `depart_after` 起跑 earliest-arrival，套用誤點，回 **live-adjusted 最早抵達 itinerary**：`legs[]`（每段 train_no、from/to station + name、dep_time、arr_time、delay_min、source）+ 總 `duration_min` + `arrival_time`。無可達班次 → 空 + note。
- **Interface / data shape**：輸入 `from`（StationID）、`to`（StationID）、`depart_after`（`HH:mm`，預設 now Asia/Taipei）、`system`（enum `[TRA]`）。輸出如上。
- **Failure modes**：缺參數 / invalid system（非 TRA）→ decoding error；無可達班次 → 空 + note（非 error）；OD 時刻表 HTTP 500/空 → 回空 + note（graceful，不 crash）；TrainLiveBoard 不可用 → 全程 scheduled + note；TDX network/rate-limit → 沿用 TDXClient surface。
- **Acceptance criteria**：
  1. 離線單元測試：fixture 時刻表（3 班 A→B，不同到時）+ fixture live board（最早表訂班誤點），`rail_route` 回的 itinerary 因誤點改選較晚但實際更早到的班次（證明 live-adjusted 路徑改變）。
  2. 離線：無誤點資料時回全 scheduled itinerary、source 標 scheduled。
  3. 離線：depart_after 之後無班次 → 空 + note，非 error。
  4. `rail_route` 註冊後 tools/list = 23、`MCPJSONRPCSmokeTest` 斷言更新（22→23、rail_ prefix +1）。
  5. 離線 `swift test` 全綠不需網路；OD 時刻表 HTTP 500 路徑以 mock 驗 graceful（回空 + note）。
  6. Live（TDX 恢復後）：`rail_route(台北→台中, now, TRA)` 回合理最早抵達 itinerary。
- **Scope boundaries**：in scope = TRA 單模態、OD 端點回傳班次的 time-dependent earliest-arrival + 即時誤點調整、新 tool/model 重用/註冊/docs。out of scope = 多模態、捷運/公車、全網非-OD 轉乘、CSA、THSR、票價、door-to-door、改動 MetroGraph。

## Risks / Trade-offs

- **主資料源當前不穩**：`DailyTrainTimetable` OD 端點今日整日回 HTTP 500（v0.4.0/v0.5.0 contract suite 唯一紅項）。Stage 1 的核心輸入正是它 → graceful degradation 是必需（回空 + note），且 criterion 6 的 live 驗證可能需等 TDX 恢復；離線測試（criteria 1–5）不受影響。
- **時刻跨午夜**：`HH:mm` 比較需處理跨日（次日 00:30）；v1 限「查詢起算 24h 內」，跨午夜以 +1440 分處理。
- **OD 端點的轉乘涵蓋有限**：OD API 主要回直達班次，全網轉乘 itinerary 需完整時刻表 → 明列為範圍外，避免假裝支援。
- **誤點對應**：TrainLiveBoard 以 trainNo 對應；若某班無即時資料則該班 scheduled（不臆測）。
- **time-expanded 圖規模**：單一 OD 的班次數小（數十班），Dijkstra 微秒級；全網才需 CSA，本 change 不需要。

## Migration Plan

純增量：新 tool + 重用既有 model + 既有 registry 端點（railTimetableOD / railTrainLiveBoard 已存在，無新端點）。rollback = 移除 TimetableRouter + 取消註冊 + 還原 docs/smoke count。

## Open Questions

- `depart_after` 是否接受日期（跨日查詢）——v1 限當日 + 24h 視窗，之後可擴充。
- 多 itinerary 候選（最早抵達 vs 最少轉乘）——v1 先回單一最早抵達；候選集待全網轉乘上線再加。
