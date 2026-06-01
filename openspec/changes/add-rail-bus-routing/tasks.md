# Tasks: Rail→Bus Multi-modal Routing (Stage 3b, first slice)

TDD throughout（`.spectra.yaml` `tdd: true`）。Spec Example（中壢→臺北轉乘→公車）即驗收案例。複用 `MultimodalRouter`（rail）+ `BusRouter`（bus）+ name-matching。

## 1. RailBusRouter 純合成邏輯 + 測試

- [x] 新增 `Sources/CheTransportMCP/Tools/RailBusRouter.swift`：(1) `busStopMatchesStation(stopName:stationName:) -> Bool` — 正規化 `臺`→`台` 後，比對 pattern `捷運<X>站` / `<X>車站` / `<X>火車站`（**不**用裸 `<X>` 以免站名為行政區時 over-match）；(2) `compose(...)` — 輸入 rail itinerary（`MultimodalRouter.Itinerary`，含 arrival 時刻）+ 每個 candidate boarding stop 的 bus options（`BusRouter.Option`，board 已用 railArrival+walk 當 departAfter 算）+ transferWalkMin，輸出最早抵達的 rail→walk→bus 合成 itinerary（legs = rail legs + bus leg、transfers = transfer 站 + walk_min、arrival_time/duration_min/transfer_count；frequency-only bus → arrival null + note）。
- [x] 新增 `Tests/CheTransportMCPTests/RailBusRouterTests.swift`：(a) name-match — `市政府`↔`捷運市政府站`、`臺北`↔`臺北車站(忠孝)`（臺/台 norm）皆 match；`南港`↔`南港行政中心(南港車站)` match 但 `南港高工` **reject**；(b) stitch — bus board ≥ rail arrival + walk；(c) frequency-only bus → arrival null + note；(d) 多 candidate → 選最早抵達。
- 驗收：`RailBusRouterTests` 四類綠。

## 2. rail_bus_route 工具 + executor（依賴 1）

- [x] `TransitTools.swift` 新增 `rail_bus_route` Tool 定義（from, transfer, to_stop, city required；depart_after optional）+ `handleCall` dispatch + `executeRailBusRoute`：解析 from/transfer（rail，沿用 transit_route resolution）+ to_stop（bus，沿用 bus stop 搜尋；多筆 → matches NSQL）；rail leg 用 `MultimodalRouter.route(from→transfer)` 取 arrival；於 city bus stops 用 `RailBusRouter.busStopMatchesStation` 篩出 transfer 站的 candidate 上車站；對每個 candidate 用 `BusRouter.route`（**a2BySig 留空 = A2 disabled**，departAfter = railArrival + transferWalk）找直達 to_stop 的 bus option；交 `RailBusRouter.compose` 選最早抵達。
- [x] 行為：rail 不可達 / 無 name-matched 且直達 to_stop 的上車站 → `{routes:[], note}`；ambiguous endpoint → `{matches}`；bus schedule 不可用 → board fallback headway、arrival 省略；**不改 transit_route / bus_route**。
- [x] 新增 `Tests/CheTransportMCPTests/RailBusRouteToolTests.swift`：executor 用 fixtures — (a) happy rail→bus（rail leg + transfer + bus leg）；(b) 模糊 to_stop → matches；(c) rail 不可達 → empty + note；(d) 無 qualifying 轉乘上車站 → empty + note。
- 驗收：`RailBusRouteToolTests` 四案綠。

## 3. Fixtures（與 task 2 並行需要）

- [x] 於 `Tests/CheTransportMCPTests/Fixtures/` 補 rail_bus_route 測試所需 fixture：rail（TRA station list + OD timetable from→transfer + live board）、metro（StopOfRoute/S2S/Frequency/LineTransfer，供 MultimodalRouter resolve transfer）、bus（Stop list 含 transfer 的 `捷運X站`/`X車站` 命名 stop + StopOfRoute 含該 stop→to_stop 在序 + Schedule）。重用既有 fixture 為主，僅補缺口。
- 驗收：`RailBusRouteToolTests` 能載入並通過。

## 4. [P] Smoke test 工具數 25 → 26（依賴 2）

- [x] `MCPJSONRPCSmokeTest.swift`：預期工具總數 25 → 26、斷言 `rail_bus_route` 在清單中（`transit_` prefix count 視命名而定——`rail_bus_route` 屬 `rail_` prefix，故 `rail_` 由 6→7；於 expectedPrefixCounts 同步調整並驗證總和為 26）。
- 驗收：`MCPJSONRPCSmokeTest` 綠（spawn 真實 binary，列 26 工具含 rail_bus_route）。

## 5. [P] 文件 + manifest（依賴 2）

- [x] 更新 `CLAUDE.md`（Multi-modal 區塊新增 rail_bus_route 說明 + 工具總數 26 + Stage 3b roadmap：3b-i explicit transfer 已實作、3b-ii auto-hub 待辦）、`README.md`、`README_zh-TW.md`、`mcpb/manifest.json`（26 工具含 rail_bus_route）。
- 驗收：四份文件工具數一致為 26 且含 rail_bus_route；`mcpb/manifest.json` 合法 JSON。

## 6. Build / test 全綠（依賴 1-5）

- [x] `swift build && swift test` 全綠（離線；integration / live 測試無 keychain 時 skip）。
- 驗收：離線測試 0 failures。

## 7. Live 驗證（env-cred gated，最後）

- [x] 新增 `Tests/CheTransportMCPTests/RailBusLiveTests.swift`（gated `TDX_CONTRACT`，env creds 優先於 keychain，沿用 Stage 2/3a live pattern）：對真實 TDX 跑一筆 `rail_bus_route`（如 from=中壢、transfer=臺北、to_stop=臺北車站附近某站的下游站），斷言 non-error + 結構合法（rail legs + bus leg，或 matches，或 empty+note）。以 shell 讀 keychain creds 注入 env 跑（headless 安全）。
- 驗收：live 回合理 rail→bus 行程（rail live + bus scheduled/frequency），或明確 matches / empty+note。

## Coverage map（requirement / design → task）

- Requirement "Rail-to-bus multi-modal routing with an explicit transfer" → task 2（tool/executor）+ task 1（compose）。
- Requirement "Name-matched bus-rail interchange" → task 1（busStopMatchesStation patterns + 臺/台 norm + district reject）。
- Requirement "Honest post-transfer bus-leg timing" → task 2（BusRouter a2 disabled, departAfter=railArr+walk）+ task 1（frequency-only → arrival null）。
- Requirement "Endpoint disambiguation follows NSQL discipline" → task 2（from/transfer/to_stop 多筆 → matches）。
- Requirement "Empty-is-not-error and graceful degradation" → task 2（rail 不可達 / 無 qualifying stop / schedule 不可用 graceful）。
- Design "Interchange name-matching (the crux)" → task 1 + task 2。
- Design "Decision: compose MultimodalRouter + BusRouter" → task 1 + task 2。
- Design "Implementation Contract acceptance" → tasks 1,2,4,6,7。
