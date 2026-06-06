## 1. Swift 套件改名（binary 核心）

- [x] 1.1 Package.swift 的 product / executableTarget / testTarget `CheTransportMCP`→`Rush`、`CheTransportMCPTests`→`RushTests`，並 git mv `Sources/CheTransportMCP`→`Sources/Rush`、`Tests/CheTransportMCPTests`→`Tests/RushTests`（spec: Unified Rush Product Identity）（驗證：`swift build` 產出名為 Rush 的 executable、`swift test` 全過）
- [x] 1.2 確認 keychain service 字串維持不變：rename 後 `Sources/Rush/Auth.swift` 的 `defaultService` 仍為 `che-transport-tdx`（spec: Preserved Credential Service）（驗證：grep 該檔出現且僅出現 `che-transport-tdx`，未被改成 rush）

## 2. Plugin shell 改名

- [x] 2.1 [P] `plugin/.claude-plugin/plugin.json`：`name`→`rush`、`version` 與 `binaryVersion`→`1.0.0`，description 同步為現況 27 工具（spec: Unified Rush Product Identity）（驗證：plugin.json `name=rush`、`version=1.0.0`、`binaryVersion=1.0.0`）
- [x] 2.2 [P] `.claude-plugin/marketplace.json`：marketplace `name` 與 plugins[] 的 `name`→`rush`、description 更新、`source` 維持 `./plugin`（spec: Self-Marketplace Distribution）（驗證：marketplace.json `name=rush`、plugin entry `name=rush`、source `./plugin`）
- [x] 2.3 `plugin/.mcp.json`：MCP server key 維持 `transport`，`command` 指向新的 `rush-wrapper.sh`（spec: Preserved Tool Surface）（驗證：.mcp.json server key 仍為 `transport`、command 路徑為 `${CLAUDE_PLUGIN_ROOT}/bin/rush-wrapper.sh`）
- [x] 2.4 git mv `plugin/bin/che-transport-mcp-wrapper.sh`→`plugin/bin/rush-wrapper.sh`，內容把下載資產名改為 `Rush`、release 來源改為 `PsychQuant/rush`，保留 binaryVersion-pinned 下載 + atomic swap 機制（.sha256 sidecar 仍隨 release 發布）（spec: Release-Pinned Binary Auto-Download）（驗證：wrapper `REPO=PsychQuant/rush`、`BINARY_NAME=Rush`、由該 repo releases 抓 `Rush` 資產並 atomic swap；release 另發 `Rush.sha256`）
- [x] 2.5 更新 plugin 內所有 binary/plugin 名引用：`plugin/hooks/session-start.sh`、`plugin/tests/test-session-start.sh`、`plugin/skills/setup-tdx/SKILL.md`、`plugin/README.md`、`plugin/CLAUDE.md`（`CheTransportMCP`→`Rush`、`che-transport-mcp`→`rush`；勿動 `che-transport-tdx`）（spec: Unified Rush Product Identity）（驗證：grep `plugin/` 無殘留 `CheTransportMCP`／`che-transport-mcp`，唯一保留的是 keychain 字串 `che-transport-tdx`）

## 3. Build / release pipeline 改名

- [x] 3.1 `Makefile` 與 `scripts/build-mcpb.sh`：binary 名 `CheTransportMCP`→`Rush`、mcpb 輸出前綴改為 `rush-X.Y.Z`（spec: Unified Rush Product Identity）（驗證：`make build` 產出 `Rush`、build-mcpb 產出 `rush-1.0.0.mcpb` + `.sha256`）

## 4. GitHub repo 改名 + 發布 Rush 1.0.0

- [x] 4.1 改名 GitHub repo（`gh repo rename rush`，owner 執行）、更新本地 git remote、確認舊 URL redirect 生效（spec: Unified Rush Product Identity）（驗證：`gh repo view PsychQuant/rush` 成功、本地 `git remote -v` 指向 rush）
- [x] 4.2 跑 sign+notarize+release pipeline，發布 `Rush` 1.0.0 binary + `.sha256` + mcpb 到 rush repo releases（spec: Release-Pinned Binary Auto-Download）（驗證：`gh release view` 顯示 rush repo 上有 `Rush` 資產與 `Rush.sha256` sidecar）

## 5. 外部引用更新

- [ ] 5.1 [P] 從中央 `psychquant-claude-plugins` 移除 che-transport entry 與過時的 `plugins/che-transport-mcp` 副本（self-marketplace 為唯一 canonical；既有使用者靠遷移說明改裝 rush）（spec: Documented Migration for Existing Installs）（驗證：中央 marketplace.json 已無 che-transport entry、無 plugins/che-transport-mcp 目錄）
- [ ] 5.2 [P] 更新 che-mcps umbrella 對此 repo 的引用與 umbrella CLAUDE.md 的 submodule 表→rush（spec: Unified Rush Product Identity）（驗證：umbrella CLAUDE.md 該列為 rush、submodule 指向新名/redirect 可解析）
- [x] 5.3 [P] 更新頂層 `CLAUDE.md`、`README.md`、`README_zh-TW.md`→rush，加入既有安裝的遷移說明（卸載 che-transport-mcp、安裝 rush），並註記 keychain service 仍為 `che-transport-tdx`（spec: Documented Migration for Existing Installs）（驗證：README 含遷移段落、CLAUDE.md 提及 rush 且註明 keychain 維持 che-transport-tdx）

## 6. 驗收

- [ ] 6.1 全新 self-marketplace 安裝驗收：add rush repo 為 marketplace、install rush、確認 wrapper 抓到 Rush binary（sha256 過）且 27 工具載入（spec: Self-Marketplace Distribution）（驗證：乾淨環境安裝後 27 工具皆可呼叫）
- [ ] 6.2 憑證延續驗收：以 rename 前已存在的 `che-transport-tdx` 憑證，Rush binary 跑 OAuth 驗證成功、不需重設（spec: Preserved Credential Service）（驗證：`make check-auth`（rush 版）以既有憑證通過）
