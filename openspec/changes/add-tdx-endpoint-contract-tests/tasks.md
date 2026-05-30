## 1. 對 TDX swagger 核對並建立 endpoint registry（單一事實來源）

- [x] 1.1 對 TDX swagger（用已登入 TDX 的 Safari 或官方 SampleCode）逐一核對 23 個 endpoint 路徑，特別確認 THSR 版本前綴（v2 vs v3，TRA 已知 v3）、traffic 三條路徑（News / Live Freeway / CCTV）、各 metro 系統 v2 路徑。本任務實現 design 決策「建立 registry 時對 TDX swagger 核對並修正 #4」。完成時：產出核對過的路徑對照，每條標明所屬 mode、回應形狀（array/object）、對應 decode model。驗證：對照涵蓋現有 7 mode 全部 tool 用到的 endpoint，無遺漏。
- [x] 1.2 建立 TDXEndpoints registry 型別於 `Sources/CheTransportMCP/TDXEndpoints.swift`，收錄 1.1 核對後的正確路徑與 metadata，對外提供「依 mode + 操作取得 path」查詢介面。本任務實現 design 決策「endpoint 路徑集中為單一事實來源 registry」，滿足 spec requirement "TDX endpoint paths have a single source of truth"。完成時：registry 即為所有 TDX endpoint 路徑的單一事實來源，production code 與 contract test 都引用它。驗證：swift build 通過；新增一個 unit test 斷言 registry 可列舉的 endpoint 條目數等於預期值。

## 2. Production 引用 registry 並修正 #4

- [x] 2.1 [P] 將 `Sources/CheTransportMCP/Models/RailModels.swift` 的 rail 路徑改為引用 registry，套用核對後的 THSR 版本修正（落實 "TDX endpoint paths have a single source of truth" 於 rail）。完成時：RailModels 不再有 v2/v3 路徑字面值，THSR 路徑為正確值。驗證：grep `Sources/CheTransportMCP/Models/RailModels.swift` 無 endpoint 路徑字面值；既有 RailModelsTests 仍綠。
- [x] 2.2 [P] 將 `Sources/CheTransportMCP/Tools/TrafficTools.swift` 的 traffic 三條路徑改為引用 registry，套用核對後的正確路徑。完成時：traffic 路徑為正確值。驗證：grep `Sources/CheTransportMCP/Tools/TrafficTools.swift` 無路徑字面值；既有 TrafficToolsTests 仍綠。
- [x] 2.3 [P] 將 `Sources/CheTransportMCP/Tools/RailTools.swift`、`AirTools.swift`、`BusTools.swift`、`BikeTools.swift`、`ParkingTools.swift`、`MaritimeTools.swift` 與 `Sources/CheTransportMCP/TDXClient.swift` 改為引用 registry。完成時：各 Tools 無 endpoint 路徑字面值。驗證：grep `Sources/CheTransportMCP/Tools/` 確認除引用 registry 外無 v2/v3 路徑字面值；各對應 ToolsTests 仍綠。
- [x] 2.4 確認 production 引用 registry 後 #4 解決。完成時：rail_search_stations、rail_find_trains（THSR）、traffic_incidents 對真實 TDX 回非 404 且可 decode。驗證：手動跑這三個查詢（或暫以 3.1 contract test 覆蓋）得非 404 + 成功 decode。

## 3. 全 endpoint contract test

- [x] 3.1 建立 contract test 群組於 `Tests/CheTransportMCPTests/ContractTests.swift`，列舉 registry 全部非靜態 endpoint，每個發真實 TDX 請求並依序斷言三層：HTTP 非 404、HTTP 200、回應 decode 成 registry 標註的 model。本任務實現 design 決策「contract test 驗證三層：非 404、HTTP 200、可 decode」，滿足 spec requirement "Each non-static endpoint has a live contract test"。完成時：每個非靜態 endpoint 有對應 contract 斷言。驗證：有憑證時 `TDX_CONTRACT=1 swift test` 跑全 endpoint 綠。
- [x] 3.2 讓 contract test 在無 TDX 憑證時整組 skip 而非 fail（檢查 keychain / CI secret 缺失即 XCTSkip），滿足 spec requirement "Contract tests skip when credentials are absent"。完成時：無憑證環境 `swift test` 不因 contract test fail。驗證：在無憑證環境跑 `swift test`，contract 群組顯示 skipped、整體不 fail。
- [x] 3.3 將既有 `Tests/CheTransportMCPTests/RailIntegrationTests.swift` 併入 contract 架構，移除與 ContractTests 重複的 rail station 測試並改由 registry 列舉驅動，消除 dead code 與路徑耦合。完成時：rail 的 contract 不再 hardcode v3/Rail/THSR/Station 路徑字面值。驗證：grep `Tests/CheTransportMCPTests/RailIntegrationTests.swift` 無獨立 endpoint 路徑字面值。

## 4. Contract test CI（nightly + release-gate，不阻擋 PR）

- [x] 4.1 新增 `.github/workflows/contract-tests.yml`，以 nightly 排程 + workflow_dispatch + release gate 三種觸發跑 `TDX_CONTRACT=1 swift test`，憑證由 GitHub Actions repo secret 注入；contract test 不在一般 PR 觸發。本任務實現 design 決策「contract test 走 nightly + release-gate，不阻擋一般 PR」，滿足 spec requirement "Contract tests run on schedule, not on every pull request"。完成時：contract test 僅於這三種觸發執行，既有 PR CI 維持只跑 mock unit test。驗證：手動 workflow_dispatch 觸發一次跑綠；檢查既有 PR CI workflow 未加入 contract job。

## 5. 驗證收尾

- [x] 5.1 執行四項 acceptance criteria 全面驗證。完成時：(1) `swift test`（mock unit）全綠且不需網路、(2) `TDX_CONTRACT=1 swift test` 全 endpoint 綠、(3) #4 的三個查詢實測非 404、(4) production code 內無 registry 以外的 TDX 路徑字面值。驗證：四項各自的指令／grep 結果逐項記錄於 #4 的驗證 comment。
