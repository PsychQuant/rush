# Related Issues & External References

Cross-references to issues, discussions, and external projects relevant to `che-transport-mcp`.

## Open issues (other repos)

### `PsychQuant/issue-driven-development#111`

> Adopt superpowers-style pre-implementation staging; reference superpowers in README

URL: <https://github.com/PsychQuant/issue-driven-development/issues/111>

**Filed**: 2026-05-20, during this project's brainstorming/writing-plans session.

**Why it's here**: This project was built using `superpowers:brainstorming → superpowers:writing-plans → superpowers:subagent-driven-development` — a three-stage flow. The experience surfaced that IDD (issue-driven-dev) plugin lacks an equivalent pre-implementation stage. Issue #111 proposes adopting similar staging in IDD and credits superpowers.

**Relevance to this project**: If IDD adopts staging, future projects can stay within a single plugin family (IDD) end-to-end. For now, this project uses both plugins (IDD for issue tracking + superpowers for staging).

## External projects referenced

### `kiki830621/NSQL`

URL: <https://github.com/kiki830621/NSQL>

**What it is**: A confirmation protocol — AI parses user request into `function + arguments`, renders the parsed form back to the user, and only executes after confirmation.

**Relevance**: `CLAUDE.md` mandates LLM agents using this MCP follow NSQL discipline before any tool call. Especially important for ambiguous queries like 「中山站」(multiple systems have same-named stations) or 「下一班」(time anchor unclear).

### TDX 運輸資料流通服務

URL: <https://tdx.transportdata.tw/>

**What it is**: Taiwan's Ministry of Transportation Maas data exchange API. Source of all transport data this MCP queries.

**Account registration**: <https://tdx.transportdata.tw/register> (free).

**API reference**: <https://tdx.transportdata.tw/api-service/swagger>

**Free tier limits**:
- 50 requests per minute
- 2 million requests per day

### `modelcontextprotocol/swift-sdk`

URL: <https://github.com/modelcontextprotocol/swift-sdk>

Version used: 0.12.x (declared `.upToNextMinor(from: "0.12.0")` in `Package.swift`).

**Note**: The plan's initial pseudocode used `server.registerTool(tool) { ... }`, but the actual 0.12 API uses `server.withMethodHandler(ListTools.self)` + `server.withMethodHandler(CallTool.self)` with switch-by-name dispatch. This divergence was caught at Plan 1 Task 10 by referencing `che-ical-mcp/Sources/CheICalMCP/Server.swift`.

## Sibling MCP projects (same author)

These live under `che-mcps/` and follow the same Developer ID sign + notarize pipeline:

| Project | Purpose |
|---------|---------|
| `che-ical-mcp` | Apple Calendar + Reminders (reference for MCP swift-sdk patterns) |
| `che-telegram-mcp` | Telegram (TDLib + Bot API) |
| `che-zotero-mcp` | Zotero reference management |
| `che-apple-mail-mcp` | Apple Mail |
| `che-apple-notes-mcp` | Apple Notes |
| `che-word-mcp` | Microsoft Word documents |
| `che-pdf-mcp` | PDF reading + manipulation |
| `che-latex-mcp` | LaTeX compilation + preview |
| `che-duckdb-mcp` | DuckDB analytics |

## Plugin distribution

This project is planned to be distributed via `psychquant-claude-plugins` marketplace once Plan 5 (release pipeline) ships. End users will install via:

```
claude plugin install che-transport-mcp@psychquant-claude-plugins
```

Until then, manual install from this git repo + `make setup-tdx`.
