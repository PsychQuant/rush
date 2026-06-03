# Tasks: migrate the remaining four tools onto RaptorCore (Stage 3c-ii.3)

TDD throughout（`.spectra.yaml` `tdd: true`）。**行為保持**：四個 tool 的 frozen 測試（`RailBusRouteToolTests`／`BusRailRouteToolTests`／`BusRouteToolTests`／`MetroToolsTests`）為 regression oracle，**不可編輯這些檔**，遷移後 0 edit 全綠。只改 `RaptorCore.swift` + `TransitTools.swift` + `BusTools.swift` + `MetroTools.swift`（+ `RaptorCoreTests.swift` 加 facade 斷言）。工具數維持 27、不發 release。單模式 tool 的 facade 為結構性委派（誠實 caveat：非 ensemble/multi-transfer 能力）。

## 1. RaptorCore 兩個委派 facade + 測試

- [x] `RaptorCore.swift` 新增 `planBusDirect(candidates:a2BySig:scheduleBySig:nowMin:departAfterMin:weekday:) -> [BusRouter.Option]`——直接委派 `BusRouter.route(...)`、原樣回傳；及 `planMetroRoutes(graph:from:to:) -> [MetroGraph.Path]`——回 `[shortestPathByTime, shortestPathByTransfers]`（nil 跳過、保持此順序）。兩者不改委派引擎輸出、不經 RaptorStrategy rounds。
- [x] `RaptorCoreTests.swift` 加斷言：(a) `planBusDirect` 對同一組 candidates/A2/schedule 回傳與 `BusRouter.route` 相同的 option 序列（route/board/arrival 逐項）；(b) `planMetroRoutes` 對一個小 MetroGraph 回傳與 `shortestPathByTime`+`shortestPathByTransfers` 相同的 path 序列（stations 序列逐項）。
- 驗收：facade 斷言綠。

## 2. composeRailLeg 改走 RaptorCore.plan（rail_bus_route + bus_rail_route）（依賴 1）

- [x] `TransitTools.swift` `composeRailLeg`：將內部 `MultimodalRouter.route(...)` 改為 `RaptorCore.plan(from:to:departAfterMin:inputs:strategies:[ComposedStrategy(), RaptorStrategy()])`（`inputs` 由該 helper 既有的 traConnections/metroData/queryDate 組），取回 `Journey` 重建 `MultimodalRouter.Itinerary(legs:transfers:arrMin:)` 後沿用既有回傳路徑。一處改動同時覆蓋 rail_bus_route 的兩條呼叫（explicit/auto）與 bus_rail_route 的呼叫。
- [x] 行為：rail_bus_route 與 bus_rail_route emitted JSON byte-identical。
- 驗收：`RailBusRouteToolTests` 與 `BusRailRouteToolTests` **0 edit 全綠**。

## 3. bus_route 改走 planBusDirect（依賴 1）

- [x] `BusTools.swift` `executeBusRoute`：把直接呼叫 `BusRouter.route(...)` 改為 `RaptorCore.planBusDirect(...)`（同參數），其餘 candidate 組裝、A2/schedule fetch、payload 格式不動。
- [x] 行為：bus_route emitted JSON byte-identical。
- 驗收：`BusRouteToolTests`（與 `BusToolsTests`）**0 edit 全綠**。

## 4. metro_find_route 改走 planMetroRoutes（依賴 1）

- [x] `MetroTools.swift` `candidateRoutes`：把內部 `graph.shortestPathByTime` + `graph.shortestPathByTransfers` 兩次呼叫改為 `RaptorCore.planMetroRoutes(graph:from:to:)` 回傳的 path 陣列，其餘 dedup/assemble/sort/cap 不動。
- [x] 行為：metro_find_route emitted JSON byte-identical（含 by-time + by-transfers 多路徑、排序、上限）。
- 驗收：`MetroToolsTests` **0 edit 全綠**。

## 5. Build / test 全綠 + 隔離驗證（依賴 1-4）

- [x] `swift build && swift test` 全綠；`MCPJSONRPCSmokeTest` 仍 27 工具；`transit_route` 套件 + 3c-ii.1 等價 harness 仍綠。
- [x] 隔離驗證：`git status` 僅 `RaptorCore.swift`、`TransitTools.swift`、`BusTools.swift`、`MetroTools.swift`、`RaptorCoreTests.swift` 有改動；四個 tool 的測試檔（`RailBusRouteToolTests`／`BusRailRouteToolTests`／`BusRouteToolTests`／`MetroToolsTests`）git diff 為空。
- 驗收：離線測試 0 failures；隔離驗證通過。

## 6. [P] CLAUDE.md roadmap（依賴 2-4）

- [x] 更新 `CLAUDE.md` Stage 3 roadmap：標 **3c-ii.3（已實作，內部）**：四 tool 全數委派 `RaptorCore`（rail_bus_route／bus_rail_route 經 composeRailLeg→plan；bus_route／metro_find_route 經委派 facade，結構性、非 ensemble 能力），全部 5 tool 現皆 dispatch 經核心、行為 byte-identical、各以 frozen 測試為 gate；工具數維持 27。下一步 `journey_plan` ≥2-transfer 依需求驅動。
- 驗收：CLAUDE.md 反映 5 tool 全遷移、誠實 caveat、journey_plan 為後續。

## Coverage map（requirement / design → task）

- Requirement "Delegating facades for single-mode tools" → task 1（planBusDirect + planMetroRoutes + 斷言）。
- Requirement "All routing tools dispatch through the core" → task 2（rail composers）+ task 3（bus_route）+ task 4（metro_find_route）+ task 5（全綠 + 隔離）。
- Design "one clean seam + two delegating facades" → tasks 1,2,3,4。
- Design "Implementation Contract acceptance" → tasks 2,3,4,5。
