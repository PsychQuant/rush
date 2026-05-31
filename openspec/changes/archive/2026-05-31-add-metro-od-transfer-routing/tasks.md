## 1. LineTransfer model 與 registry 端點

- [x] 1.1 在 `Sources/CheTransportMCP/Models/MetroModels.swift` 新增 `MetroLineTransfer` Codable（FromLineID/FromStationID/FromStationName、ToLineID/ToStationID/ToStationName、IsOnSiteTransfer、TransferTime、TransferDescription），欄位對齊 diagnose 實測的 TDX shape。新增 fixture `Tests/CheTransportMCPTests/Fixtures/metro_line_transfer.json`（真實 shape，含板橋 BL07↔Y16 一筆）。完成時：model 可 decode LineTransfer 回應。驗證：`MetroModelsTests` 新增一例 decode fixture 成功並斷言 TransferTime。
- [x] 1.2 在 `Sources/CheTransportMCP/TDXEndpoints.swift` 新增 `metroLineTransfer(_ sys)` builder（`v2/Rail/Metro/LineTransfer/{op}`，dataset 在 operator 前）+ 代表系統 TRTC contract case，落實 design 決策「LineTransfer 進 registry + 單線系統 graceful」與 spec requirement "Metro routing endpoints in the registry"。完成時：LineTransfer 路徑只在 registry 定義、contract case 列舉涵蓋。驗證：`TDXEndpointsTests` contract case 數 30→31 並斷言 + metroLineTransfer 路徑斷言；grep TDXEndpoints 外無 LineTransfer 路徑字面值。

## 2. 站網圖、最短路徑、與 metro_find_route 改寫

- [x] 2.1 新增 `Sources/CheTransportMCP/Tools/MetroGraph.swift`，落實 design 決策「一律建圖跑最短路徑（取代 #5 gate）」與「MetroGraph 為內部 helper（新檔，同 module），on-demand 建構」：由 StationOfRoute + S2STravelTime + LineTransfer 建圖（node=站；同線相鄰邊雙向，權重 = RunTime + 中間站 StopTime，沿用 #5 方向無關 lookup；轉乘邊雙向，權重 = TransferTime + 目的線 headway/2），跑 Dijkstra by total time 回最短路徑（站序列 + 用到的線/換乘）。新增 `MetroGraphTests` 驗四情境：最短路徑正確、環狀捷徑勝過長程直達、單線系統無轉乘邊仍可回同線路徑、不可達回 nil/空。完成時：給 from/to 回最短路徑或無路徑。驗證：MetroGraphTests 綠（含環狀捷徑 + 單線 graceful + 不可達）。
- [x] 2.2 改寫 `Sources/CheTransportMCP/Tools/MetroTools.swift` 的 `metro_find_route` executor，落實 design 決策「擴充 metro_find_route，輸出統一為 legs」「轉乘成本 = TransferTime（步行）+ headway/2（等車，估計）」「最佳 = 最短時間，回 ≤3 候選 + 最少轉乘」與 spec requirement "Metro O/D routing tool"：移除 #5 direct short-circuit gate，改為一律 fetch 五個 dataset（含 LineTransfer，HTTP 400/空以 try? 容錯為空）→ 建圖 → 取最短時間 + 最少轉乘候選（≤3，去重，依時間升冪）→ 組裝 `routes[].legs[]`（每段 line_name/color + 該段 travel_time_min/headway_min）+ `transfers[]`（station + from_line/to_line + walk_min + wait_min）+ transfer_count + 總 travel_time_min。不可達回空 routes + note（empty ≠ error）。更新 `MetroToolsTests`：直達 regression（北車→南港回 1 leg/0 transfer）、轉乘情境（北車→淡水回 ≥1 transfer 含 walk+wait）、候選排序、不可達回空。完成時：直達與轉乘同一 legs 形狀、輸出含 transfer_count。驗證：MetroToolsTests 綠（直達 regression + 轉乘 + 不可達三情境）。

## 3. docs 與驗證收尾

- [x] 3.1 [P] 更新 `CLAUDE.md`：`metro_find_route` 說明改為「直達 + 跨線轉乘最短路徑」，輸出形狀註明 legs/transfers，工具數維持 22（擴充既有 tool）。完成時：CLAUDE.md 反映轉乘能力。驗證：grep CLAUDE.md `metro_find_route` 段含「轉乘」。
- [x] 3.2 [P] 更新 `README.md`、`README_zh-TW.md`：metro O/D 條目改為含轉乘，工具數維持 22。完成時：兩 README 反映轉乘能力。驗證：grep 兩 README `metro_find_route` 條目含 transfer/轉乘。
- [x] 3.3 [P] 更新 `mcpb/manifest.json`：`metro_find_route` tool description 改為含轉乘，tools 陣列仍 22 筆。完成時：manifest metro_find_route 描述含轉乘。驗證：python json.load 通過且 tools 數 22。
- [x] 3.4 執行 design 五項 acceptance criteria 全面驗證：(1) 北車→淡水(TRTC) 回 transfer_count≥1 + walk/wait；(2) 直達 regression 北車→南港回 0-transfer 板南線；(3) LineTransfer 進 registry + contract case、`TDX_CONTRACT=1` 含該端點綠、contract 數 31；(4) 離線 swift test 全綠含 MetroGraphTests；(5) tool 數仍 22、smoke 綠；(6) grep production 無 registry 以外 metro 路徑字面值。完成時：六項逐項通過。驗證：各項指令／grep 結果逐項記錄於 #6 驗證 comment。
