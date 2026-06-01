# Tasks: Multi-modal TRA↔Metro Routing (Stage 2)

TDD throughout (`.spectra.yaml` `tdd: true`)：先寫測試（RED）→ 最小實作（GREEN）→ 重構。Spec examples（中壢→西門）即驗收案例。

## 1. Probe 真實 TDX 取得 interchange 站點 ID（前置，阻擋 task 2）

- [x] 對真實 TDX 查 TRA 與 TRTC 在 台北車站 / 板橋 / 南港 / 松山 的實際 `StationID`（TRA 用 `rail_search_stations`、TRTC 用 metro station 資料），記錄成一張對映表（含每站的 TRA id、TRTC line + id、估計 `walk_min`）。
- 驗收：對映表四站皆有 TRA id + 至少一個 TRTC id，記錄在 design 的 registry 區塊或 task comment（real-data，非臆測 — #4/#5 教訓）。

## 2. [P] InterchangeRegistry — 策劃式交會站表

- [x] 新增 `Sources/CheTransportMCP/Tools/InterchangeRegistry.swift`：`struct Interchange { name; traStationID; trtcStationIDs: [String]; walkMin: Int }` + 一個 static `entries` 表（用 task 1 的真實 ID）+ 查詢函式（給 TRA id 或 TRTC id 回對應交會點）。
- [x] 新增 `Tests/CheTransportMCPTests/InterchangeRegistryTests.swift`：sanity test — 每個 entry 的 `traStationID` 非空、`trtcStationIDs` 至少一筆、`walkMin` 落在 1...30；查詢函式雙向命中。
- 驗收：`InterchangeRegistryTests` 綠；registry 涵蓋 task 1 的四站。

## 3. [P] 確認 TimetableRouter / MetroGraph 可被 MultimodalRouter 重用（minimal）

- [x] 確認 `TimetableRouter.earliestArrival` / `connections` / `clock` / `minutesOfDay` 與 `MetroGraph.shortestPathByTime` 可從同 module 的 `MultimodalRouter` 呼叫；若有 `private`/access 阻擋則做最小 visibility 調整，**不改 `rail_route` / `metro_find_route` 行為**。
- 驗收：既有 `TimetableRouterTests` + `MetroToolsTests` 全綠（兩個既有 router 行為不變）。

## 4. MultimodalRouter — mixed scheduled+frequency 時間相依搜尋（依賴 2、3）

- [x] 新增 `Sources/CheTransportMCP/Tools/MultimodalRouter.swift`：**time-anchored multi-leg composition** — reuse `TimetableRouter.earliestArrival`（TRA legs，live delay）+ `MetroGraph.shortestPathByTime`（metro legs，graph 用 metro-entry band 建）+ interchange registry。枚舉 registry 交會點組 `[TRA→交會點] + [walk] + [metro→終點]`（與反向 metro-first），metro 進入時加 entry-line first-boarding wait `headway(band)/2`，選終點 arrival 最早者。同系統行程 delegate 給對應 router。回 legs（TRA legs + metro ride runs 併段）+ transfers + arrival_time + duration_min + transfer_count。
- [x] 新增 `Tests/CheTransportMCPTests/MultimodalRouterTests.swift`：(a) TRA→metro composition 選出最早到達的交會點路徑；(b) metro entry 用 `headway(band)/2` expected-wait；(c) entry-band — metro 進入時段決定該段 headway；(d) 經 registry 交會點轉乘，`transfers[]` 帶 `walk_min`。
- 驗收：`MultimodalRouterTests` 四案綠。

## 5. transit_route 工具 + executor（依賴 4）

- [x] 新增 `Sources/CheTransportMCP/Tools/TransitTools.swift`：`defineTools()`（`transit_route(from, to, depart_after?)` schema，required from/to）、`register(into:client:cache:)`、`handleCall`、`executeRoute`（解析 from/to 跨 TRA+TRTC；fetch origin→候選交會點的 `DailyTrainTimetable` OD + `TrainLiveBoard` + MetroGraph 資料 + registry → `MultimodalRouter`；輸出 legs/transfers/arrival_time/duration_min/transfer_count）。
- [x] 行為：endpoint 多系統同名 → 回 `{matches:[...]}`（NSQL，不臆測）；不可達 → `{routes:[], note}`；TRA timetable 500/空 → `{routes:[], note}` 不 crash；metro-only 行程不需 TRA fetch。
- [x] 新增 `Tests/CheTransportMCPTests/TransitToolsTests.swift`：executor 用 fixtures — (a) 多模式 happy path（中壢→西門 形態：TRA leg live + 交會轉乘 + metro frequency leg）；(b) 模糊 endpoint → matches；(c) TRA timetable 不可用 → graceful note；(d) metro-only 行程。
- 驗收：`TransitToolsTests` 四案綠。

## 6. 接上 fixtures（與 task 5 並行需要）

- [x] 視 task 5 測試需要，於 `Tests/CheTransportMCPTests/Fixtures/` 補上 transit 測試所需 fixture（origin→交會點的 TRA OD timetable、對應 live board；metro s2s/frequency/line 已存在則重用）。
- 驗收：`TransitToolsTests` 能載入所需 fixture 並通過（`Bundle.module` 解析成功）。

## 7. 註冊到 Server（依賴 5）

- [x] 在 `Sources/CheTransportMCP/Server.swift` 的 registry 區塊加入 `await TransitTools.register(into: registry, client: client, cache: cache)`。
- 驗收：server 啟動後 `transit_route` 出現在 `ListTools`。

## 8. Smoke test 工具數 23 → 24（依賴 7）

- [x] 更新 `Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift`：預期工具總數 23 → 24，並斷言 `transit_route` 在清單中。
- 驗收：`MCPJSONRPCSmokeTest` 綠（spawn 真實 binary，列出 24 工具含 transit_route）。

## 9. [P] 文件 + manifest（依賴 7）

- [x] 更新 `CLAUDE.md`（Rail 區塊新增 transit_route 說明 + 工具總數 24 + Stage 2 roadmap 註記）、`README.md`、`README_zh-TW.md`、`mcpb/manifest.json`（24 工具，含 transit_route 定義）。
- 驗收：四份文件工具數一致為 24，皆含 transit_route 條目；`mcpb/manifest.json` 合法 JSON。

## 10. Build / test / live 驗證（最後）

- [x] `swift build && swift test` 全綠（離線；integration 測試無 keychain 時 skip）。
- [x] Live 驗證 `transit_route(中壢→西門, now)` 回合理多模式行程（TRA live leg + 台北車站 轉乘 + 板南線 frequency leg）；若 TDX `DailyTrainTimetable` 仍 500，標記 blocked-on-TDX 並以 metro-only 行程 + graceful note 佐證 degradation 路徑。
- 驗收：離線全綠；live 行程合理或明確標 blocked-on-TDX。

## Coverage map（requirement / design → task）

每個 spec requirement 與 design 主題對映到實作它的 task：

- Requirement "Multi-modal TRA↔Metro earliest-arrival routing" → task 5（transit_route 工具 + executor）。
- Requirement "Expected-wait frequency model for metro legs" → task 4（MultimodalRouter frequency edge）。
- Requirement "Live-delay-adjusted TRA legs" → task 4（TRA scheduled edge，live-delay 折入）。
- Requirement "Curated interchange registry for cross-system transfers" → task 1（probe ID）+ task 2（InterchangeRegistry）。
- Requirement "Endpoint disambiguation follows NSQL discipline" → task 5（from/to 多系統同名 → matches）。
- Requirement "Graceful degradation and empty-is-not-error" → task 5（TRA timetable 500/空 + 不可達 → routes:[] + note）。
- Design topic "Why time-dependent Dijkstra (not the alternatives)" → task 4（演算法選定）。
- Design topic "Node graph" → task 4（TRA ∪ TRTC ∪ interchange 節點圖）。
- Design topic "Edge cost = time-dependent arrival" → task 4（三類時間相依邊成本）。
- Design topic "depart_after anchor" → task 5（depart_after 預設 now、起點 label）。
- Design topic "from/to resolution (NSQL discipline)" → task 5（跨系統解析 + 模糊回 matches）。
