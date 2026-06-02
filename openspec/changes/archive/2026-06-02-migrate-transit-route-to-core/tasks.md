# Tasks: migrate transit_route onto RaptorCore (Stage 3c-ii.2)

TDD throughout（`.spectra.yaml` `tdd: true`）。**行為保持**：`TransitToolsTests` 為 frozen regression oracle，**不可編輯該檔**，遷移後必須 0 edit 全綠。只改 `RaptorCore.swift` + `TransitTools.swift`（+ `RaptorCoreTests.swift` 加斷言）；其餘四 tool 與引擎不動。工具數維持 27、不發 release（behavior-preserving、無使用者可見變化）。

## 1. Journey 加 transfers + 兩 strategy 填入 + 測試

- [x] `RaptorCore.swift`：`Journey` 新增 `transfers: [MultimodalRouter.Transfer]`（與 legs/arrivalMin 並列）；`ComposedStrategy` 由 `it.transfers` 填入（精確）；`RaptorStrategy` 由其 chain 上的 footpath edge（walkMin + at 站 id/name）best-effort 填入。`transferCount` 維持 `legs.count-1`（不依 transfers）。
- [x] `RaptorCoreTests.swift` 加斷言：對 metro→metro（含一次跨線或無跨線）與既有 floor 測試輸入，`ComposedStrategy().plan(...)?.transfers` 等於對應 `MultimodalRouter.route(...)?.transfers`（at/atName/walkMin 逐項）。
- 驗收：新斷言綠；既有 `RaptorCoreTests` 全綠。

## 2. transit_route executor 改走 RaptorCore + payload 由 Journey 重建（依賴 1）

- [x] `TransitTools.swift` `executeRoute`：將原本的 `MultimodalRouter.route(...)` 呼叫（與其 guard/empty note）改為 `RaptorCore.plan(from:to:departAfterMin:inputs:strategies:[ComposedStrategy(), RaptorStrategy()])`，`inputs` 由既有 fetch 的 `traConnections`/`metroData`/`Date()` 組成；取回的 `Journey` 重建為 `MultimodalRouter.Itinerary(legs:transfers:arrMin:)` 後交給**現有未改的** `routePayload`。nil journey → 同今日 empty-routes + note。endpoint 解析與 fetch 不動。
- [x] 行為：emitted JSON byte-identical（legs/transfers/arrival_time/duration_min/transfer_count、matches、empty+note 全同）。**不改** `transit_route` schema/dispatch、不改其他四 tool。
- 驗收：`TransitToolsTests` **0 edit 全綠**（regression oracle）。

## 3. Build / test 全綠 + 隔離驗證（依賴 1-2）

- [x] `swift build && swift test` 全綠；`MCPJSONRPCSmokeTest` 仍 27 工具；3c-ii.1 等價 harness（`RaptorTransitEquivalenceTests`）仍綠。
- [x] 隔離驗證：`git status` 僅顯示 `Sources/CheTransportMCP/Tools/RaptorCore.swift`、`Sources/CheTransportMCP/Tools/TransitTools.swift`、`Tests/CheTransportMCPTests/RaptorCoreTests.swift` 有改動；`TransitToolsTests.swift` 與其餘四 tool／引擎檔 git diff 為空。
- 驗收：離線測試 0 failures；隔離驗證通過（無預期外檔案改動）。

## 4. [P] CLAUDE.md roadmap（依賴 2）

- [x] 更新 `CLAUDE.md` Stage 3 roadmap：標 **3c-ii.2（已實作，內部）**：`transit_route` 已遷移為委派 `RaptorCore` ensemble（行為 byte-identical、frozen 測試為 gate）；列出剩餘四 tool（rail_bus_route／bus_rail_route／bus_route／metro_find_route）待後續增量遷移；工具數維持 27、無使用者可見變化。
- 驗收：CLAUDE.md 反映 transit_route 已上核心、剩餘遷移清單。

## Coverage map（requirement / design → task）

- Requirement "Journey carries transfers" → task 1（Journey.transfers + 兩 strategy 填入 + 斷言）。
- Requirement "transit_route delegates to the routing core" → task 2（executor 改走 plan + payload 重建 + frozen oracle 全綠）+ task 3（隔離驗證、其餘 tool 未動）。
- Design "delegate the route call, reconstruct the same payload" → task 2。
- Design "Journey must carry transfers" → task 1。
- Design "Implementation Contract acceptance" → tasks 2,3。
