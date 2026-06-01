# Tasks: Direct-route Bus Routing (Stage 3a)

TDD throughout（`.spectra.yaml` `tdd: true`）：先測（RED）→ 最小實作（GREEN）→ 重構。Spec 的 Example（671 直達）即驗收案例。

## 1. [P] Bus/Schedule endpoint + 模型

- [x] `TDXEndpoints.swift` 新增 `busSchedule(_ city:) = v2/Bus/Schedule/City/\(city)`，並加 contract case（`bus.Taipei.schedule`）。
- [x] `BusModels.swift` 新增 `BusSchedule { routeID, routeName, subRouteID?, direction, frequencys: [BusFrequency], timetables: [BusTimetable] }`、`BusFrequency { startTime, endTime, minHeadwayMins, maxHeadwayMins, serviceDay }`、`BusTimetable { tripID, serviceDay, stopTimes: [BusScheduleStopTime] }`、`BusScheduleStopTime { stopSequence, stopID, arrivalTime, departureTime }`、`BusServiceDay`（weekday Int flag 0/1），CodingKeys 對齊 TDX 欄位（Frequencys/Timetables/StopTimes/ArrivalTime/DepartureTime）。
- 驗收：模型可由真實 TDX 形狀的 JSON decode。

## 2. [P] BusSchedule decode 測試

- [x] `Tests/CheTransportMCPTests/BusModelsTests.swift`（或新增）加 BusSchedule decode case：一筆含 `Timetables`（per-stop ArrivalTime/DepartureTime）、一筆只含 `Frequencys`（headway band），bare-or-wrapped 經 `TDXDecode.list` 皆可解。
- 驗收：兩種形狀皆 decode 成功，欄位值正確。

## 3. BusRouter 純路由邏輯 + 測試（依賴 1）

- [x] 新增 `Sources/CheTransportMCP/Tools/BusRouter.swift`（pure）：輸入 candidate routes（含 stop sequence + direction）、A2 arrivals、BusSchedule、origin/dest stop、departAfter；輸出 `routes[]`（board_in_min + board_source、arrival_time + arrival_source 或 null+note、direction、board/alight stop）。board 取 A2 live > timetable 次班 departure > frequency `MinHeadwayMins/2`；arrival 僅 timetabled 用 trip 的 dest ArrivalTime − origin DepartureTime 加到 board，frequency-only → null + note。依 earliest arrival（已知時）否則 soonest board 排序。
- [x] 新增 `Tests/CheTransportMCPTests/BusRouterTests.swift`：(a) timetabled route → board + arrival（ride-time delta 正確）；(b) frequency-only route → board 有值、arrival null + note；(c) A2 live 優先於 schedule fallback；(d) direction + stop sequence 過濾（origin 必須在 dest 之前、同 direction）；(e) sub-route case（同 route 多 sub-route，只取真正服務兩站者）。
- 驗收：`BusRouterTests` 五案綠。

## 4. bus_route 工具 + executor（依賴 3）

- [x] `BusTools.swift` 新增 `bus_route` Tool 定義（from_stop, to_stop, city required；depart_after optional）、在 `handleCall` dispatch、新增 `executeBusRoute`：解析 from/to stop（沿用 bus stop 搜尋；多筆同名 → `{matches}` NSQL）；fetch `StopOfRoute(city)` 取 candidate routes（sequence+direction，沿用 bus_find_routes 交集邏輯）；fetch A2 `EstimatedTimeOfArrival(city)` 以 `$filter=StopID eq` 限縮到 origin stop；fetch `Bus/Schedule(city)`；交給 `BusRouter`。
- [x] 行為：無直達 → `{routes:[], note}`（提示尚不支援轉乘，非錯誤）；A2 不可用 → board fallback schedule/headway 不報錯；schedule 不可用 → board 仍用 A2、arrival 省略。**不改 `bus_find_routes`**。
- [x] 新增 `Tests/CheTransportMCPTests/BusRouteToolTests.swift`：executor 用 fixtures — (a) happy path（直達、board+arrival）；(b) 模糊 stop → matches；(c) 無直達 → empty + note；(d) A2 missing → graceful（board 改 schedule/headway）。
- 驗收：`BusRouteToolTests` 四案綠。

## 5. Fixtures（與 task 4 並行需要）

- [x] 於 `Tests/CheTransportMCPTests/Fixtures/` 補 bus_route 測試所需 fixture：`bus_stop_of_route.json`（含 origin/dest 在序、direction）、`bus_estimated_arrival.json`（A2，含一筆有 EstimateTime）、`bus_schedule.json`（一筆 Timetables + 一筆 Frequencys）。
- 驗收：`BusRouteToolTests` 能載入並通過（`Bundle.module` 解析成功）。

## 6. Smoke test 工具數 24 → 25（依賴 4）

- [x] `MCPJSONRPCSmokeTest.swift`：預期工具總數 24 → 25、`bus_` prefix 5 → 6、斷言 `bus_route` 在清單中。
- 驗收：`MCPJSONRPCSmokeTest` 綠（spawn 真實 binary，列 25 工具含 bus_route）。

## 7. [P] 文件 + manifest（依賴 4）

- [x] 更新 `CLAUDE.md`（Bus 區塊新增 bus_route 說明 + 工具總數 25 + Stage 3a roadmap 註記）、`README.md`、`README_zh-TW.md`、`mcpb/manifest.json`（25 工具含 bus_route）。
- 驗收：四份文件工具數一致為 25 且含 bus_route；`mcpb/manifest.json` 合法 JSON。

## 8. Build / test 全綠（依賴 3-7）

- [x] `swift build && swift test` 全綠（離線；integration / live 測試無 keychain 時 skip）。
- 驗收：離線測試 0 failures。

## 9. Live 驗證（env-cred gated，最後）

- [x] 新增 `Tests/CheTransportMCPTests/BusRouteLiveTests.swift`（gated `TDX_CONTRACT`，env `TDX_CLIENT_ID/SECRET` 優先於 keychain，沿用 Stage 2 TransitLiveTests pattern）：對真實 TDX 跑一筆同城直達 `bus_route`，斷言 board 有值（live 或 fallback）、arrival timetabled 有值 / frequency null。以 shell 讀 keychain creds 注入 env 跑（headless 安全）。
- 驗收：live 回合理直達（board live/fallback 皆可、arrival 依 route 型態），或服務時段外明確 fallback；非 service-hour 時 board 走 frequency 亦算通過。

## Coverage map（requirement / design → task）

- Requirement "Direct-route within-city bus routing" → task 4（tool）+ task 3（BusRouter candidate+sequence+direction）。
- Requirement "Live board-ETA with honest fallback" → task 3（board A2 > schedule > headway）。
- Requirement "Timetable-backed arrival or honest omission" → task 3（arrival delta or null）+ task 1（BusSchedule Timetables 模型）。
- Requirement "Stop disambiguation follows NSQL discipline" → task 4（from/to 多筆 → matches）。
- Requirement "Empty-is-not-error and graceful degradation" → task 4（無直達 / A2 或 schedule 不可用 graceful）。
- Design "Bus/Schedule endpoint + model" → task 1 + task 2。
- Design "Algorithm (per query)" → task 3 + task 4。
- Design "Implementation Contract acceptance" → tasks 3,4,6,8,9。
