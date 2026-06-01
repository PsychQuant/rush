## 1. Connection 與即時誤點資料解析

- [x] 1.1 落實 design 決策「Connection 模型沿用 RailODFare / RailStopTime」：確認 `RailODFare`/`RailStopTime` 能 decode `DailyTrainTimetable` OD（trainInfo + stopTimes 含 arrivalTime/departureTime），必要時補欄位；確認 `RailLiveTrain` 能 decode `TrainLiveBoard`（trainNo + delayTime）。新增 fixtures `Tests/CheTransportMCPTests/Fixtures/tra_timetable_od.json`（3 班 A→B，不同到時）與 `tra_train_live_board.json`（含一班誤點）。完成時：兩 model 可 decode 對應 fixture。驗證：`RailModelsTests` 新增二例 decode 並斷言 stopTimes 時刻 / delayTime。

## 2. Time-expanded 路由與即時誤點調整

- [x] 2.1 新增 `Sources/CheTransportMCP/Tools/TimetableRouter.swift`，落實 design 決策「time-expanded earliest-arrival Dijkstra（CSA 之後再換）」：由 `[RailODFare]` 建 time-expanded 圖（node=(站,時刻) 事件、edge=同班車相鄰停靠 ride 邊 + 同站候車邊），從 (from, depart_after) 跑 earliest-arrival Dijkstra（cost=抵達時刻，`HH:mm`→分、跨午夜 +1440）。新增 `TimetableRouterTests` 驗：表訂最早抵達正確、depart_after 後無班次回 nil。完成時：給 from/to/depart_after 回最早抵達 itinerary 或 nil。驗證：TimetableRouterTests 綠（最早抵達 + 無可達）。
- [x] 2.2 落實 design 決策「即時誤點調整：TrainLiveBoard DelayTime 平移班次時刻」與「新鮮度標註 + graceful degradation」、spec requirement "Live-delay adjustment and freshness labelling"：建圖前用 `[RailLiveTrain]` 的 DelayTime 平移對應 trainNo 的時刻，重算 earliest-arrival；每段標 `source: live|scheduled`；無即時資料的班次標 scheduled。完成時：誤點會改變選出的 itinerary。驗證：`TimetableRouterTests` 加 spec Example（X 08:00→09:00 誤點 15 分、Y 08:10→09:05 準點 → 選 Y）與「無 live 資料 → 全 scheduled fallback」二情境。

## 3. rail_route tool、註冊、tool count

- [x] 3.1 新增 `rail_route(from, to, depart_after?, system)` tool（system enum 僅 `TRA`、depart_after 預設 now Asia/Taipei）於 `Sources/CheTransportMCP/Tools/RailTools.swift` + executor，落實 design 決策「新 tool `rail_route`，不擴充 `rail_find_trains`」與 spec requirement "TRA time-dependent earliest-arrival routing tool"：fetch `railTimetableOD` + `railTrainLiveBoard`（OD HTTP 500/空以 try? graceful → 回空 + note；live 不可用 → 全 scheduled + note）→ 解析 → 呼叫 TimetableRouter → 組裝 itinerary（legs[]：train_no/from/to/dep_time/arr_time/delay_min/source + 總 duration_min + arrival_time）。在 `Sources/CheTransportMCP/Server.swift` 註冊。完成時：rail_route 回 live-adjusted itinerary，缺資料 graceful。驗證：`RailToolsTests`（或新 test）驗 mock 直達最早抵達、OD 不可用回空+note、非 TRA system 回 error。
- [x] 3.2 更新 `Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift`：tool 總數 22→23、`rail_` prefix 5→6（其餘不變），滿足 design acceptance criterion (4)。完成時：tools/list 回 23、rail_ 計 6。驗證：MCPJSONRPCSmokeTest 綠。

## 4. docs 與驗證收尾

- [x] 4.1 [P] 更新 `CLAUDE.md`：Rail 段加 `rail_route` 條目（時刻表 time-dependent 最早抵達 + 即時誤點，僅 TRA），工具數 22→23。完成時：CLAUDE.md 含 rail_route。驗證：grep CLAUDE.md 有 rail_route + 23。
- [x] 4.2 [P] 更新 `README.md`、`README_zh-TW.md`：新增 rail_route 條目、工具數 22→23。完成時：兩 README 含 rail_route。驗證：grep 兩 README 有 rail_route + 23。
- [x] 4.3 [P] 更新 `mcpb/manifest.json`：tools 陣列加 rail_route、long_description 工具數 22→23。完成時：manifest tools 含 rail_route。驗證：python json.load 通過且 tools 數 23。
- [x] 4.4 執行 design 六項 acceptance criteria 全面驗證：(1) 誤點改變選班、(2) 無 live 回 scheduled、(3) 無可達回空+note、(4) tool 數 23+smoke 綠、(5) 離線 swift test 全綠含 OD-500 graceful mock、(6) live（TDX 恢復後）台北→台中合理最早抵達。完成時：六項逐項通過（live 項若 TDX timetable 仍 500 則記錄為 blocked-on-TDX，不阻擋離線收尾）。驗證：各項指令／grep 結果逐項記錄於 Stage 1 的驗證紀錄。
