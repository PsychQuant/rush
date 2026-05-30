## Context

che-transport-mcp 透過 TDX（運輸資料流通服務）Open API 提供 7 種運具、23 個 MCP tool。每個 tool 在 `Tools/` 或 `Models/` 內 hardcode 一段 TDX endpoint 路徑（例如 rail 的版本前綴 v2/v3、bus 的 v2/Bus/...）。

現有測試 101 個全用 MockURLProtocol，攔截 HTTP，只驗 client 行為。路徑字串本身對不對沒有任何測試覆蓋。PsychQuant/che-transport-mcp#4 即因此漏網：rail（THSR/TRA）與 traffic endpoint 實測 404，但 air 正常、OAuth 正常。既有 RailIntegrationTests 雖真打 TDX，但 skip-if-no-keychain 使其在 CI 永遠跳過、本地少跑，且與 production 共用同一 hardcoded 路徑，無獨立事實來源。

約束：TDX free tier rate limit 50 requests/min；TDX 憑證存於 macOS keychain（service che-transport-tdx）；CI 在 GitHub Actions macOS runner 跑。

## Goals / Non-Goals

**Goals:**

- 把 23 個 TDX endpoint 路徑集中成單一事實來源，production code 與測試都引用它。
- 每個非靜態 endpoint 有一個真打 TDX 的 contract test，能在路徑漂移（404）或 schema 變動（decode 失敗）時失敗。
- 修正 #4 的 rail/traffic 路徑（建立 registry 時對 swagger 核對）。
- contract test 的執行策略不讓 TDX 偶發網路問題阻擋一般 PR。

**Non-Goals:**

- 不改動任何 MCP tool 的對外 JSON schema 或工具簽章（純內部重構 + 測試）。
- 不新增 MCP tool、不改 cache TTL / retry / OAuth 邏輯。
- 不追求 contract test 涵蓋所有 query 參數組合，每個 endpoint 一個最小 smoke 即可。
- 不把 contract test 設為每次 PR 必跑（被否決，理由見 Decisions）。

## Decisions

### Endpoint 路徑集中為單一事實來源 registry

新增一個 Swift 型別（enum 或 struct，置於 `Sources/CheTransportMCP/TDXEndpoints.swift`），把 23 個路徑字串集中定義，附帶每個 endpoint 的 metadata（所屬 mode、預期回應是 array 或 object、對應的 decode model 型別）。production code（各 Tools/Models）改為引用此 registry 而非各自 hardcode。

理由：#4 的根因是「路徑散落 + 測試與正式碼各自 hardcode 同一字串」，沒有單一可驗證點。集中後，contract test 可以列舉 registry 全部條目逐一打，新增 endpoint 時若忘了加 contract 也能由列舉偵測到。

替代方案：維持路徑分散、只在測試端複製一份路徑清單。否決——複製清單會與 production 不同步，重蹈 #4 的耦合覆轍。

### Contract test 驗證三層：非 404、HTTP 200、可 decode

每個非靜態 endpoint 一個 contract test，依序斷言：(1) HTTP 狀態非 404（路徑字串正確）、(2) HTTP 200（請求被接受）、(3) 回應 body 能 decode 成 registry 標註的 model 型別（schema 對應）。靜態 tool（如 rail_list_systems 回 hardcoded 清單）不需 contract test。

理由：三層由淺到深對應三種失敗模式——路徑漂移、權限/參數錯、schema 變動。#4 是第一層（404）；未來 TDX 改欄位會被第三層抓到。

替代方案：只驗非 404。否決——schema 變動（TDX 改欄位名）會讓 production decode 失敗但 contract test 仍綠，留下盲點。

### Contract test 走 nightly + release-gate，不阻擋一般 PR

contract test 與既有 unit test 分離（獨立 test 群組，以環境變數如 TDX_CONTRACT 啟用；無憑證時 skip）。CI 安排：unit（mock）每次 PR 跑；contract（真打 TDX）走 nightly 排程 + release 前必跑 + 手動 workflow_dispatch，憑證由 GitHub Actions repo secret 注入。

理由：單輪約 24 個 request 不會撞 50/min rate limit，但 TDX 偶發網路/維護會讓 contract test flaky；若設為每次 PR 必跑，無辜 PR 會因 TDX 抖動而 CI 變紅。endpoint 路徑漂移是低頻事件，nightly + release gate 已能及時偵測。

替代方案：每次 PR 都跑 contract test。否決——flaky 阻擋無關 PR，且重複消耗 rate limit。

### 建立 registry 時對 TDX swagger 核對並修正 #4

填 registry 時逐一對 TDX 官方 API 文件核對每個路徑，校正 THSR 版本前綴（目前 v3 疑為 v2，TRA 已確認 v3）與 traffic 路徑（v2/Road/Traffic/News 等實測 404）。修正後 registry 即為正確值，production 引用後 #4 自動解決。

理由：registry 重構本就要逐一檢視每個路徑，順勢核對是零額外成本的修復點，且修正落在單一事實來源處，不會遺漏某個散落的 hardcode。

## Implementation Contract

- **Behavior**：完成後，每個非靜態 MCP tool 對真實 TDX 發出的請求都能接得上（非 404）；rail（THSR/TRA 時刻與站點）、traffic（路況/事件/CCTV）這些原本 404 的查詢回正常資料。endpoint 路徑只有 registry 一處定義。
- **Interface / data shape**：新增 TDXEndpoints registry 型別，對外提供「依 mode + 操作取得 path 字串」的查詢介面，並標註每條 endpoint 的回應形狀與 decode model。各 Tools 改呼叫此介面取得 path，不再內嵌字串字面值。contract test 以可列舉的方式走訪 registry 全部條目。
- **Failure modes**：contract test 失敗代表兩種情況之一——HTTP 404/非200（endpoint 路徑漂移或權限問題）或 decode 失敗（TDX schema 變動）。兩者都明確 surface 於 test 報告，不靜默吞掉。無憑證環境下 contract test 整體 skip（非 fail），維持 CI 對無 secret PR 的相容。
- **Acceptance criteria**：(1) `swift test`（unit/mock）維持全綠且不需網路；(2) 啟用 TDX_CONTRACT 且有憑證時，全 endpoint contract test 綠；(3) registry 修正後，#4 列出的 rail_search_stations / rail_find_trains（THSR）與 traffic_incidents 三個查詢實測非 404；(4) production code 內不再有 registry 以外的 TDX 路徑字面值（可由 grep 驗證）。
- **Scope boundaries**：in scope = TDXEndpoints registry、各 Tools 改引用、#4 路徑修正、全 endpoint contract test、contract CI workflow。out of scope = MCP tool 對外 schema、新 tool、cache/retry/OAuth 邏輯、query 參數的窮舉測試。

## Risks / Trade-offs

- [TDX swagger 需登入才能查完整 endpoint 清單] → 用已登入 TDX 的 Safari（peichun 帳號）查，或參考 TDX 官方 GitHub SampleCode 公開範例核對。
- [contract test flaky（TDX 偶發維護/網路）] → 不設為 PR 必跑；nightly 失敗時人工判斷是真漂移還是暫時抖動；release gate 失敗可手動重跑確認。
- [rate limit 50/min] → 單輪約 24 request 安全；若未來 endpoint 大幅增加需分批或加間隔。
- [GitHub Actions repo secret 存 TDX 憑證] → TDX free tier 憑證敏感度低（可隨時於會員中心重新產生）；用 repo secret 而非寫入 code，且 contract workflow 不在 fork PR 觸發（避免 secret 外洩）。

## Migration Plan

純增量，無資料遷移。部署順序：先加 registry 並讓 production 引用（含 #4 路徑修正）→ 加 contract test → 加 CI workflow。rollback：contract test 與 CI 為新增檔案，移除即可；registry 重構若出問題可暫時 revert 至原 hardcode（但會帶回 #4）。

## Open Questions

- THSR 確切版本前綴（v2 vs v3）需以 TDX swagger 最終確認。
- traffic 三個 endpoint（News / Live Freeway / CCTV）的確切現行路徑需逐一核對。
- 各 metro 系統（TRTC/TYMC/KRTC/TMRT/NTDLRT/KLRT）的 v2 路徑是否全部仍有效，待 contract test 首次執行揭露。
