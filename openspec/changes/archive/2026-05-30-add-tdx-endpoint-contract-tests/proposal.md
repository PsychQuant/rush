## Why

che-transport-mcp 的 101 個既有 test 全部以 MockURLProtocol 攔截 HTTP，只驗證 client 收到假回應後的行為（retry / OAuth / dispatch / JSON sanitize），從不對真實 TDX 發出請求。因此「endpoint 路徑字串對不對」這一層完全沒有測試覆蓋——這正是 PsychQuant/che-transport-mcp#4 漏網的原因：rail（THSR/TRA）與 traffic 的 TDX data endpoint 實測全部回 404，但 air 正常、OAuth 正常，憑證無誤。現有的 RailIntegrationTests 雖然真打 TDX，卻因 skip-if-no-keychain 在 CI 永遠跳過、本地也少有人手動跑，形同 dead code，且只覆蓋 rail 的 2 個 endpoint。

## What Changes

- 新增 TDX endpoint 路徑的 single source of truth registry（集中 23 個散落在 Tools 與 Models 的路徑字串），production code 與 contract test 都改引用它，消除「測試與正式碼各自 hardcode 同一路徑」的耦合。
- 建立 registry 時對 TDX 官方 swagger 逐一核對每個 endpoint 路徑，當場修正 #4：校正 THSR 的版本前綴（疑似應為 v2 而非目前的 v3，TRA 已確認為 v3）與 traffic 的路徑（v2/Road/Traffic/News 等實測 404）。
- 為每個非靜態 endpoint 新增一個真打 TDX 的 contract test，驗證三件事：HTTP 非 404（路徑正確）、HTTP 200、回應能 decode 成對應 model（schema 對應）。
- 新增 CI workflow：contract test 走 nightly 排程 + release gate 必跑 + 手動 workflow_dispatch，使用 GitHub Actions repo secret 注入 TDX 憑證；既有 unit（mock）test 維持每次 PR 跑。**BREAKING**：無——純增量，不改動既有 MCP tool 的對外行為。

## Non-Goals

（design.md 將建立，Non-Goals 與被否決的方案記於 design.md 的 Goals/Non-Goals 段。）

## Capabilities

### New Capabilities

- `tdx-endpoint-contract`: TDX endpoint 路徑的 single source of truth registry，加上每個 endpoint 的 live contract test 驗證（路徑正確性 + schema 對應），以及 contract test 的 CI 執行策略（nightly + release-gate，不阻擋一般 PR）。

### Modified Capabilities

（無既有 spec）

## Impact

- Affected specs: 新增 `tdx-endpoint-contract`
- Affected code:
  - New:
    - `Sources/CheTransportMCP/TDXEndpoints.swift`
    - `Tests/CheTransportMCPTests/ContractTests.swift`
    - `.github/workflows/contract-tests.yml`
  - Modified:
    - `Sources/CheTransportMCP/Models/RailModels.swift`
    - `Sources/CheTransportMCP/Tools/TrafficTools.swift`
    - `Sources/CheTransportMCP/Tools/RailTools.swift`
    - `Sources/CheTransportMCP/Tools/AirTools.swift`
    - `Sources/CheTransportMCP/Tools/BusTools.swift`
    - `Sources/CheTransportMCP/Tools/BikeTools.swift`
    - `Sources/CheTransportMCP/Tools/ParkingTools.swift`
    - `Sources/CheTransportMCP/Tools/MaritimeTools.swift`
    - `Sources/CheTransportMCP/TDXClient.swift`
    - `Tests/CheTransportMCPTests/RailIntegrationTests.swift`
  - Removed: （無）
