# Tasks: Auto transfer-hub selection for rail→bus (Stage 3b-ii)

TDD throughout（`.spectra.yaml` `tdd: true`）。複用 `RailBusRouter.compose` / `busStopMatchesStation` / `composeRailLeg` / `MultimodalRouter`。explicit-transfer 3b-i 路徑不可改（byte-for-byte）。

## 1. RailBusRouter 反向搜尋 + 選擇邏輯（純函式）+ 測試

- [x] `RailBusRouter.swift` 新增：(1) `HubCandidate { railStationName, railStationID, boardingStopUID, boardingStopName, routeUID, direction }`；(2) `candidateHubs(...)` — 對每個 serving `to_stop` 的 route+direction，掃 `to_stop` 上游（index 較小、同方向）的 stop，用 `busStopMatchesStation` 比對候選 rail 站名；產出 candidate，依 `(railStation, boardingStopUID)` 去重，依「上游離 to_stop 的接近度」（boarding stop index 越接近 to_stop 越前）排序，套用 `maxAutoHubCandidates` cap（預設 8）並回報被丟棄數；(3) `selectEarliest(_ results:[Result]) -> Result?` — 把既有 earliest-arrival 排序（known arrival 先於 unknown、再比 board）提升到跨 candidate 的 stitch。
- [x] `Tests/CheTransportMCPTests/RailBusRouterTests.swift` 擴充：(a) candidateHubs 只取上游 stop（下游 stop 不算）；(b) district-name reject 沿用（上游 `南港高工` 不產生 candidate，`南港車站` 產生）；(c) 去重 — 同 `(hub, boarding)` 多 route 只留一筆；(d) cap — 超過 8 個 candidate 時截斷且回報 dropped 數；(e) proximity 排序 — boarding stop 越接近 to_stop 排越前；(f) selectEarliest — 跨多個 stitched Result 選最早 arrival、known 先於 unknown。
- 驗收：`RailBusRouterTests` 新增六類綠；既有 3b-i 純函式測試不變。

## 2. rail_bus_route auto-hub executor 分支 + schema（依賴 1）

- [x] `TransitTools.swift`：tool schema 將 `transfer` 移出 `required`（改 optional），description 說明 explicit / auto 兩模式 + `auto_selected_transfer` 輸出；`executeRailBusRoute` 在 `transfer == nil` 時走 auto 分支：解析 rail 站名清單（沿用已 fetch 的 TRA stations + TRTC station names）+ fetch `to_stop` 的 StopOfRoute → `RailBusRouter.candidateHubs` → 對每個 candidate 跑 `composeRailLeg(from→hub)` + bus leg（A2 disabled、departAfter=railArr+walk）+ `RailBusRouter.compose` → `selectEarliest` → payload 加 `auto_selected_transfer` = 選中 hub 站名 + cap note（若有）。`transfer` 有值時走既有 3b-i 路徑（不變）。
- [x] 行為：auto 模式無 qualifying hub / `from` 不可達任何 hub → `{routes:[], note}`；ambiguous `from`/`to_stop` → `matches`；cap 截斷 → note。explicit 模式輸出不含 `auto_selected_transfer`。
- [x] `Tests/CheTransportMCPTests/RailBusRouteToolTests.swift` 擴充：(a) auto happy — 省略 transfer，回 rail legs + bus leg + `auto_selected_transfer`；(b) explicit 路徑回歸 — 給 transfer 時行為同 3b-i（無 `auto_selected_transfer`）；(c) auto 無 qualifying hub → empty + note；(d) auto ambiguous to_stop → matches。
- 驗收：`RailBusRouteToolTests` 新增四案綠；既有 3b-i 四案不變。

## 3. [P] Smoke test：transfer 不再必填（依賴 2）

- [x] `MCPJSONRPCSmokeTest.swift`：工具總數維持 26、`rail_bus_route` 仍在清單；斷言 `rail_bus_route` 的 inputSchema `required` 含 `from`/`to_stop`/`city` 但**不含** `transfer`。
- 驗收：`MCPJSONRPCSmokeTest` 綠（26 工具，rail_bus_route required 不含 transfer）。

## 4. [P] 文件 + manifest（依賴 2）

- [x] 更新 `CLAUDE.md`（rail_bus_route 條目補 auto-hub 模式：省略 transfer 時 to_stop-anchored reverse search 自動選交會站、`auto_selected_transfer` 輸出、cap 揭露；Stage roadmap 標 3b-ii 已實作、3c 統一核心待議）、`README.md`、`README_zh-TW.md`、`mcpb/manifest.json`（rail_bus_route description 補 auto-hub；工具數維持 26）。
- 驗收：四份文件描述含 auto-hub + transfer optional，工具數一致 26；`mcpb/manifest.json` 合法 JSON。

## 5. Build / test 全綠（依賴 1-4）

- [x] `swift build && swift test` 全綠（離線；integration / live 測試無 keychain 時 skip）。
- 驗收：離線測試 0 failures。

## 6. Live 驗證（env-cred gated，最後）

- [x] `Tests/CheTransportMCPTests/RailBusLiveTests.swift` 擴充一個 auto-hub case（gated `TDX_CONTRACT`，env creds 優先）：省略 transfer 跑一筆 `rail_bus_route(from=中壢, to_stop=具體 StopUID, city=Taipei)`，斷言 non-error + 結構合法（rail legs + bus leg + `auto_selected_transfer`，或 matches，或 empty+note）。以 shell 讀 keychain creds 注入 env 跑（headless 安全）。
- 驗收：live 回合理 auto-hub 行程（含 auto_selected_transfer），或明確 matches / empty+note。

## Coverage map（requirement / design → task）

- Requirement "Rail-to-bus multi-modal routing with an explicit transfer"（MODIFIED：transfer optional）→ task 2（schema optional + explicit 回歸）。
- Requirement "Auto transfer-hub selection via reverse search" → task 1（candidateHubs reverse search + dedup + cap + selectEarliest）+ task 2（executor auto 分支 + auto_selected_transfer + cap note）。
- Design "to_stop-anchored reverse search" → task 1。
- Design "Candidate cap (bound + honesty)" → task 1（cap + dropped 數）+ task 2（cap note 進 payload）。
- Design "Implementation Contract acceptance" → tasks 1,2,3,5,6。
