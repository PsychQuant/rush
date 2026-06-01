# Tasks: bus→rail Multi-modal Routing (Stage 3c-i)

TDD throughout（`.spectra.yaml` `tdd: true`）。新 sibling `BusRailRouter`，複用 `RailBusRouter.busStopMatchesStation` + `HubCandidate`/`HubDiscovery` 型別、`BusRouter`（A2 enabled）、`MultimodalRouter`。`RailBusRouter` 與三個既有 tool 不可改。

## 1. BusRailRouter 純函式（forward discovery + 反向 stitch + 選擇）+ 測試

- [x] 新增 `Sources/CheTransportMCP/Tools/BusRailRouter.swift`：(1) `candidateAlightHubs(fromStopUID:routes:railStations:cap:) -> RailBusRouter.HubDiscovery` — 對每個 serving `from_stop` 的 route+direction，掃 `from_stop` **下游**（index 較大、同方向）的 stop，用 `RailBusRouter.busStopMatchesStation` 比對候選 rail 站；產出 candidate，依 `(railStation, alightStopUID)` 去重，依「下游離 from_stop 的接近度」（alight stop index 越接近 from_stop 越前）排序，套 cap（預設 `RailBusRouter.maxAutoHubCandidates`）並回報 dropped 數；(2) `Result { busOption, busBoardClockMin, hubStationName, transferWalkMin, railLegs, arrivalClockMin }` + `compose(...)` — 把一段 bus（leg 1）+ rail legs（leg 2）組成 bus→rail itinerary，`arrivalClockMin` = rail 段抵達；(3) `selectEarliest(_:) -> Result?` — 跨 candidate 選最早 rail 抵達（known 先於 unknown）。
- [x] 新增 `Tests/CheTransportMCPTests/BusRailRouterTests.swift`：(a) 只取 `from_stop` **下游** stop（上游不算）；(b) district reject 沿用（下游 `南港高工` 不產生、`南港車站` 產生）；(c) 去重；(d) cap 截斷且回報 dropped；(e) proximity — 越接近 from_stop 的下游站排越前；(f) selectEarliest 跨多 Result 選最早 rail 抵達。
- 驗收：`BusRailRouterTests` 六類綠；`RailBusRouterTests`（既有 10）不變。

## 2. bus_rail_route 工具 + executor（explicit + auto 分支）（依賴 1）

- [x] `TransitTools.swift`：新增 `bus_rail_route` Tool 定義（from_stop, to, city required；transfer, depart_after optional）+ `handleCall` dispatch + `executeBusRailRoute`：解析 `from_stop`（bus，沿用 `resolveBusStop`）+ `to`（rail，沿用 `resolveCandidates`；多筆 → matches）；fetch StopOfRoute + A2（`StopUID eq from_stop`）+ schedule；`transfer` 給定 → 用該站；省略 → `BusRailRouter.candidateAlightHubs`。每個 hub：bus leg `BusRouter.route`（**A2 enabled**，origin=from_stop、dest=hub alight stop、departAfter=depart_after）→ 取 bus Option；rail leg `MultimodalRouter.route(hub→to, departAfter = (busArr ?? busBoard)+walk)`；`BusRailRouter.compose`；`selectEarliest`。auto 時 payload 加 `auto_selected_transfer` + cap note；bus 抵達未知時加近似 note。
- [x] 行為：無 qualifying hub / `to` 不可達任一 hub / 無直達 bus → `{routes:[], note}`；ambiguous `from_stop`/`to` → `{matches}`；bus 抵達未知 → rail 以 board+walk 錨定 + 近似 note。explicit 模式不含 `auto_selected_transfer`。**不改** rail_bus_route / transit_route / bus_route。
- [x] 新增 `Tests/CheTransportMCPTests/BusRailRouteToolTests.swift`：executor 用 FIFO fixtures — (a) explicit happy bus→rail（leg1 Bus + rail legs，A2-live board source=live）；(b) auto happy（省略 transfer → `auto_selected_transfer`）；(c) ambiguous from_stop → matches；(d) 無 qualifying hub → empty + note；(e) frequency-only bus（無 schedule）→ rail board-anchored + 近似 note。
- 驗收：`BusRailRouteToolTests` 五案綠。

## 3. [P] Smoke test 工具數 26 → 27（依賴 2）

- [x] `MCPJSONRPCSmokeTest.swift`：預期工具總數 26 → 27、斷言 `bus_rail_route` 在清單；`bus_rail_route` 的 inputSchema `required` 含 `from_stop`/`to`/`city` 不含 `transfer`。prefix count：`bus_` 由 6→7（`bus_rail_route` 屬 `bus_` prefix），於 expectedPrefixCounts 同步並驗證總和 27。
- 驗收：`MCPJSONRPCSmokeTest` 綠（27 工具含 bus_rail_route）。

## 4. [P] 文件 + manifest（依賴 2）

- [x] 更新 `CLAUDE.md`（Multi-modal 區塊新增 bus_rail_route + 工具總數 27 + Stage roadmap：3c-i bus→rail 已實作、multi-transfer/RAPTOR 仍 deferred）、`README.md`、`README_zh-TW.md`、`mcpb/manifest.json`（27 工具含 bus_rail_route）。
- 驗收：四份文件工具數一致 27 且含 bus_rail_route；`mcpb/manifest.json` 合法 JSON。

## 5. Build / test 全綠（依賴 1-4）

- [x] `swift build && swift test` 全綠（離線；integration / live 測試無 keychain 時 skip）。
- 驗收：離線測試 0 failures。

## 6. Live 驗證（env-cred gated，最後）

- [x] 新增 `Tests/CheTransportMCPTests/BusRailLiveTests.swift`（gated `TDX_CONTRACT`，env creds 優先）：省略 transfer 跑一筆 `bus_rail_route(from_stop=具體 Taipei StopUID, to=南港, city=Taipei)`，斷言 non-error + 結構合法（bus leg + rail legs + `auto_selected_transfer`，或 matches，或 empty+note）。以 shell 讀 keychain creds 注入 env 跑（headless 安全）。**注意**：本 live test 與既有 RailBusLiveTests 同樣 TDX-call-heavy，背靠背跑可能觸發 50/min rate-limit；live 為 opt-in、非離線 gate。
- 驗收：live 回合理 bus→rail 行程（A2-live leg1 + rail leg2），或明確 matches / empty+note。

## Coverage map（requirement / design → task）

- Requirement "Bus-to-rail multi-modal routing" → task 2（tool/executor）+ task 1（compose）。
- Requirement "Auto alight-hub selection when transfer omitted" → task 1（candidateAlightHubs forward search + dedup + cap）+ task 2（auto 分支 + auto_selected_transfer + cap note）。
- Requirement "Honest bus-arrival timing for the rail anchor" → task 2（busArr ?? busBoard 錨定 + 近似 note）+ task 1（Result 攜 arrivalClockMin）。
- Design "forward discovery + bus-then-rail stitch" → task 1 + task 2。
- Design "The timing chain (the honest wrinkle)" → task 2（rail 錨定）+ task 1 + task 2 測試 (e)。
- Design "Implementation Contract acceptance" → tasks 1,2,3,5,6。
