## 1. Metro 資料 model 與 registry 端點

- [x] 1.1 新增 `Sources/CheTransportMCP/Models/MetroModels.swift`：StationOfRoute（含巢狀 Stations[]，每筆 StationID/StationName/Sequence）、S2STravelTime（含 TravelTimes[]）、Frequency（含 ServiceDay/OperationTime/Headways[]）、Line（LineNo/LineID/LineName/LineColor）的 Codable。完成時：四個 model 可 decode TDX 捷運回應。驗證：新增 MetroModelsTests 用 fixture decode 四種回應各一筆成功。
- [x] 1.2 在 `Sources/CheTransportMCP/TDXEndpoints.swift` 新增 4 個 metro 端點 builder（`v2/Rail/Metro/{StationOfRoute,S2STravelTime,Frequency,Line}/{op}`，dataset 在 operator 前）+ 對應 contract cases，落實 design 決策「4 個 metro 端點進 TDXEndpoints registry」與 spec requirement "Metro routing endpoints in the registry"。完成時：四端點路徑只在 registry 定義、contract case 列舉涵蓋。驗證：TDXEndpointsTests 的 contract case 數更新並斷言；grep TDXEndpoints 外無 metro routing 路徑字面值。

## 2. metro_find_route tool 與直達路由邏輯

- [x] 2.1 新增 `Sources/CheTransportMCP/Tools/MetroTools.swift`：tool 定義 `metro_find_route(from, to, system)`（system enum 為 6 個 metro 代碼）+ dispatch，落實 design 決策「新 tool metro_find_route，不擴充 rail_find_trains」與 spec requirement "Metro direct O/D routing tool"。完成時：tool schema 含 from/to/system，回傳結構含 routes 陣列。驗證：MetroTools.defineTools() 回 1 個 tool、名稱 metro_find_route。
- [x] 2.2 實作直達路由邏輯（落實 design 決策「路由邏輯資料流」「v1 只做直達（單 route 交集）」「回傳形狀：line + travel time + headway」）：StationOfRoute 找含 from+to 的單一 route 並判方向 → 用 route 的 Stations 序列定位 from/to index → S2STravelTime 累加區間旅行時間 → Frequency 取當下 Asia/Taipei ServiceDay+OperationTime 的 Headway → Line 補 LineName/LineColor → 組裝 routes（旅行時間升冪）。無直達 route 回空 matches + 轉乘提示（指 #6）。完成時：直達回線+時間+班距、無直達回空非 error。驗證：MetroToolsTests 用 mock fixture 驗交集找線、區段累加、空直達回空+提示三情境。

## 3. 註冊、tool count、docs

- [x] 3.1 在 `Sources/CheTransportMCP/Server.swift` 註冊 MetroTools；更新 `Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift` 的 tool 總數 21→22 與 per-prefix 加 `metro_`=1，滿足 design acceptance criterion (3)。完成時：tools/list 回 22、metro_ prefix 計 1。驗證：MCPJSONRPCSmokeTest 綠。
- [x] 3.2 [P] 更新 `CLAUDE.md`（加 metro_find_route 到 rail/捷運段、工具數 21→22）。完成時：CLAUDE.md tool 目錄含 metro_find_route。驗證：grep CLAUDE.md 有 metro_find_route。
- [x] 3.3 [P] 更新 `README.md`、`README_zh-TW.md`（tool 數 21→22、新增 metro O/D 條目）。完成時：兩 README 反映 22 tools + 捷運 O/D。驗證：grep 兩 README 有 metro_find_route / 22。
- [x] 3.4 [P] 更新 `mcpb/manifest.json`（tools 陣列加 metro_find_route、long_description tool 數 21→22）。完成時：manifest tools 含 metro_find_route。驗證：python json.load 通過且 tools 數 22。

## 4. 驗證收尾

- [x] 4.1 執行 design 的五項 acceptance criteria 全面驗證。完成時：(1) metro_find_route(臺北車站→南港, TRTC) 回板南線直達 + 旅行時間 + 班距；(2) TDX_CONTRACT=1 swift test 含 metro 端點全綠；(3) tool 總數 22、smoke test 綠；(4) 離線 swift test 全綠不需網路；(5) grep production 無 registry 以外 metro 路徑字面值。驗證：五項各自指令／grep 結果逐項記錄於 #5 的驗證 comment。
