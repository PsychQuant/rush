# Tasks: Unified routing core — increment 3c-ii.1 (strategy ensemble + transit_route equivalence)

TDD throughout（`.spectra.yaml` `tdd: true`）。核心原則：**多策略平行 + dominance 取最佳**，proven 組合為 floor、RAPTOR 為 upside。複用 `TimetableRouter`（TRA CSA+誤點）、`MetroGraph`（metro headway/2）、`InterchangeRegistry`、`MultimodalRouter`（組合方法 + Itinerary/Leg 形狀）。**本增量不接線任何 tool、不改五個 shipped tool 的 source、tool 數維持 27、不發 release**（純內部引擎，dead-code-until-wired）。

## 1. 輸出模型 + RoutingStrategy 介面 + dominance 選擇器 + 測試

- [x] 新增 `Sources/CheTransportMCP/Tools/RaptorCore.swift`：`Journey { legs:[Leg], arrivalMin:Int, transferCount:Int }`（Leg 對齊 `MultimodalRouter.Leg`：mode/起訖/depMin/arrMin/source）、`RoutingInputs`（聚合已 fetch 的 `traConnections`/`MetroData`/`queryDate`，不發新 fetch）、`protocol RoutingStrategy { func plan(from:to:departAfterMin:inputs:) -> Journey? }`、`RaptorCore.plan(from:to:departAfterMin:inputs:strategies:) -> Journey?`——跑所有 strategy、收集 candidate、回 dominant（最早 arrival；平手比 transferCount 少；再平手依 strategy 註冊序穩定）。
- [x] 新增 `Tests/CheTransportMCPTests/RaptorCoreTests.swift` 選擇器部分：(a) 兩 strategy 不同 arrival → 取較早；(b) arrival 平手 → 取 transfer 少；(c) 全 nil → nil；(d) 空 strategy 清單 → nil。
- 驗收：選擇器測試綠。

## 2. ComposedStrategy（floor，= MultimodalRouter 組合）+ floor 保證測試（依賴 1）

- [x] `RaptorCore.swift` 新增 `ComposedStrategy: RoutingStrategy`——委派 `MultimodalRouter.route(from:to:departAfterMin:traConnections:metro:queryDate:)`（TRA `TimetableRouter` + metro `MetroGraph` headway/2 + `InterchangeRegistry` seam），把回傳 `Itinerary` 映成 `Journey`。等價 by construction（同子引擎同成本）。
- [x] `RaptorCoreTests.swift` 加 floor 保證：對任一 from/to，`RaptorCore.plan(strategies:[Composed, Raptor]).arrivalMin <= ComposedStrategy.plan(...).arrivalMin`（ensemble 永不比 proven 晚到）。
- 驗收：floor 保證測試綠。

## 3. RaptorStrategy（round-based、≥2-transfer 可達、委派子引擎）+ 測試（依賴 1）

- [x] `RaptorCore.swift` 新增 `RaptorStrategy: RoutingStrategy`——round-based label-setting 於 inter-modal seam graph（節點 = TRA 站 + metro 站；邊 = TRA connection 最早可搭、metro 段經 `MetroGraph`（entry wait headway/2）、`InterchangeRegistry` footpath），以 `maxRounds` 限制轉乘；每站保留最早 arrival label + parent，重建 `Journey`（metro leg `source: frequency`、TRA leg `live/scheduled`）。
- [x] `RaptorCoreTests.swift` 加 RAPTOR 測試：(a) 需兩次轉乘的目的地 maxRounds≥2 找得到、maxRounds=1 找不到；(b) metro leg 貢獻 `headway/2 + ride`、source frequency；(c) 同站兩路徑取較早 arrival（label dominance）。
- 驗收：RAPTOR 測試三類綠。

## 4. transit_route 差異等價 harness（依賴 2,3）

- [x] 新增 `Tests/CheTransportMCPTests/RaptorTransitEquivalenceTests.swift`：對 `transit_route` 既有 executor fixtures（TRA→metro happy 中壢→西門 via 板橋、metro-only、TRA-only、unreachable empty）各跑一次——以同樣輸入組 `RoutingInputs`、跑 `RaptorCore.plan(strategies:[Composed, Raptor])`，斷言 ensemble 選出的 journey legs（mode+起訖+source）、arrivalMin、transferCount 等於 `transit_route` 對應輸出；empty/unreachable case 兩者一致（皆 nil/空）。
- 驗收：`RaptorTransitEquivalenceTests` 全綠（ensemble 重現 transit_route）。

## 5. [P] CLAUDE.md roadmap（依賴 3）

- [x] 更新 `CLAUDE.md` Stage 3 roadmap：標 **3c-ii.1（已實作，內部）**：`RaptorCore` 多策略 ensemble（ComposedStrategy floor + RaptorStrategy round-based）+ dominance 選擇器已落地並經差異等價驗證重現 transit_route，**尚未接線任何 tool**；後續增量（3c-ii.2+）逐一遷移 tool（各以該 tool frozen 測試為 regression gate），全部遷移後 `journey_plan` ≥2-transfer 自然產生。明記：tool 數維持 27、本增量不改使用者可見行為、誠實天花板不變（headway/2 期望，RAPTOR 加可達不加精度）；多策略原則 = proven 為 floor、新策略只增不減。
- 驗收：CLAUDE.md 反映 3c-ii.1 內部落地（ensemble 框架）+ 遷移路線，工具數仍 27。

## 6. Build / test 全綠（依賴 1-5）

- [x] `swift build && swift test` 全綠：新增測試綠 + **五個 shipped tool 的測試 0 編輯下全綠**（regression gate）+ `MCPJSONRPCSmokeTest` 仍 27 工具（無新工具）。
- 驗收：離線測試 0 failures；五 tool 測試檔 git diff 為空（未被改動）。

## Coverage map（requirement / design → task）

- Requirement "Strategy ensemble with dominance selection" → task 1（介面 + 選擇器）。
- Requirement "Proven-composition strategy as the floor" → task 2（ComposedStrategy + floor 保證測試）。
- Requirement "Round-based strategy for multi-transfer reachability" → task 3（RaptorStrategy + reachability/headway/dominance 測試）。
- Requirement "Equivalence to transit_route without rewiring" → task 4（差異 harness）+ task 6（五 tool 未改、測試全綠）。
- Design "strategy ensemble + dominance selector" → tasks 1,2,3。
- Design "Implementation Contract acceptance" → tasks 1,2,3,4,6。
