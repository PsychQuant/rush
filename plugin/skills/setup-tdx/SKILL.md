---
name: setup-tdx
description: Guide user through obtaining TDX (運輸資料流通服務) credentials and seeding them into the macOS keychain so che-transport-mcp tools can authenticate. Handles both first-time users with no TDX account (walks through registration + API-key retrieval) and users who already have credentials. Use when che-transport-mcp tools fail with "TDX auth failed" / "Missing TDX credentials" / "401", when the SessionStart banner shows "⚠ TDX credentials missing", or when the user asks to set up TDX / 註冊 TDX / 拿 TDX API key / 設定憑證. Credentials live under keychain service "che-transport-tdx" with accounts "client_id" and "client_secret".
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Setup TDX credentials for che-transport-mcp

TDX 運輸資料流通服務 is the Taiwan government open-data API that all 23 tools in this plugin query. Free tier = 50 requests/min, no card needed.

Setup has **two halves**, and it matters which one the user is stuck on:

1. **Get a TDX account + API key** — a web task on the TDX portal. A brand-new user has to register and dig the key out of the member area. This skill hand-holds that (Step 3) — it is the part people actually get stuck on.
2. **Seed the keychain** — `CheTransportMCP --setup`, an interactive flow in the signed binary that reads `client_secret` via `getpass()` (hidden), writes to keychain, and verifies with a live OAuth round-trip. This skill launches it in a **real Terminal window** so the secret never enters Claude Code's transcript.

Do NOT seed the keychain via the Bash tool with the secret inline — that leaks it into the conversation log. Always go through the Terminal-window path (Step 5) or have the user run `--setup` in their own terminal.

## Step 1: Check if already seeded

```bash
security find-generic-password -s che-transport-tdx -a client_id  >/dev/null 2>&1 \
  && security find-generic-password -s che-transport-tdx -a client_secret >/dev/null 2>&1 \
  && echo "SEEDED" || echo "MISSING"
```

If `SEEDED`: credentials already exist. Ask if the user wants to re-run setup anyway (rotated / wrong key). If not, stop — just remind them to `Cmd+Q` + reopen Claude Code if tools still fail.

If `MISSING`: proceed.

## Step 2: Does the user already have a TDX API key?

This is the branch point. Ask with `AskUserQuestion`:

> 你已經有 TDX 的 `client_id` 和 `client_secret` 了嗎？

- **Options**: "有，憑證在手邊" / "沒有，需要先申請" / "不確定 / 不知道那是什麼"
- "有" → skip to **Step 4**
- "沒有" or "不確定" → do **Step 3** first

Never assume the user has credentials. A first-time plugin user almost certainly does not — the SessionStart banner saying "⚠ TDX credentials missing" only means the keychain is empty, not that they have a key ready to paste.

## Step 3: Register a TDX account + retrieve the API key

This is a **web task** — it cannot be automated. Walk the user through it conversationally and stay with them; answer questions as they go.

### 3a. Register

Offer to open the registration page:

```bash
open "https://tdx.transportdata.tw/register"
```

Registration is free, no credit card, ~2 minutes. A standard account is usable right after signup; the 學研單位 (academic) tier additionally goes through a review step before the key activates — most users want the standard account.

### 3b. Retrieve client_id + client_secret

Once registered and logged in, the API key is **not** shown on the landing page. Guide them through the exact path:

1. Top-right corner → **會員中心**
2. → **資料服務**
3. → **API 金鑰**
4. A key pair already exists by default. Click the green **編輯** button on that row to reveal **Client Id** and **Client Secret**.
5. Copy **both** values somewhere safe (Notes, password manager) — the secret is not always re-displayed later.

Notes to relay:
- Each account may hold up to **3** API keys (新增 API 金鑰 to add more) — one is plenty here.
- If the user can't find 會員中心 / the menu wording differs, the portal UI may have changed — have them look for any "API 金鑰" / "API Key" entry under the member/account area, or check the TDX 介接指南.
- Do NOT ask the user to paste the values into the chat. They only need them in hand for Step 5, typed into a separate Terminal window.

Wait until the user confirms they have both values before continuing.

## Step 4: Pick the credential-entry path

Two paths exist; **prefer (A)**. The preference is purely UX — both paths have the same security property (typed values never enter this Claude Code session).

### (A) `che-keychain` is installed → direct native dialog

Detect:

```bash
which che-keychain >/dev/null 2>&1 || [ -x ~/bin/che-keychain ] && echo "PRESENT" || echo "ABSENT"
```

If `PRESENT`, invoke directly via the Bash tool. che-keychain pops a native NSAlert (`client_id` visible + `client_secret` masked, in **one** dialog). User types into that dialog; this Claude Code session never sees the values.

```bash
che-keychain set-pair \
  --service che-transport-tdx \
  --visible-account client_id \
  --secure-account client_secret \
  --visible-label "TDX client_id" \
  --secure-label "TDX client_secret" \
  --title "che-transport-mcp — TDX setup" \
  --explain "Free TDX account: https://tdx.transportdata.tw/register  •  會員中心 → 資料服務 → API 金鑰 → 編輯"
```

Exit codes from the Bash tool: `0` stored, `2` user cancelled, other → error (see stderr).

After exit `0`, run the OAuth verification step yourself via the CheTransportMCP binary (skip to **Step 6**):

```bash
~/bin/CheTransportMCP --check-auth
```

Tell the user clearly:

> 已彈出 che-keychain 對話框 — 請在**那個視窗**輸入 client_id / client_secret。client_secret 全程不會經過這裡的對話。完成後我會自動驗證。

If `che-keychain` is `ABSENT`, point the user at <https://github.com/PsychQuant/che-keychain> as a one-time install, OR proceed with path (B).

### (B) Fallback — Terminal window running the binary's built-in `--setup`

If `che-keychain` isn't installed (or the user doesn't want to install it), launch the plugin's launcher shim in a real Terminal window. The shim forwards to `wrapper --setup` → `CheTransportMCP --setup` (getpass-based; CheTransportMCP v0.2.2+ also auto-detects che-keychain itself, so if che-keychain shows up later this same shim picks it up).

Locate the shim:

```bash
SETUP=$(ls ~/.claude/plugins/cache/*/che-transport-mcp/*/bin/setup-tdx.sh 2>/dev/null | sort -V | tail -1)
[ -z "$SETUP" ] && SETUP=$(find ~/.claude/plugins -path '*che-transport-mcp*/bin/setup-tdx.sh' -type f 2>/dev/null | sort -V | tail -1)
```

If still empty, the plugin install is broken — tell the user to `/plugin install che-transport-mcp@psychquant-claude-plugins`.

Launch:

```bash
open -a Terminal "$SETUP"
```

Tell the user:

> 已開了一個 Terminal 視窗。請在**那個視窗**裡完成 — client_secret 用 getpass 隱藏輸入，全程不會經過這裡的對話。完成後回來告訴我。

Then wait for the user to report back.

## Step 6: Confirm result

After the user says they're done, re-check:

```bash
security find-generic-password -s che-transport-tdx -a client_id  >/dev/null 2>&1 \
  && security find-generic-password -s che-transport-tdx -a client_secret >/dev/null 2>&1 \
  && echo "SEEDED ✓" || echo "STILL MISSING"
```

If still missing, the user likely aborted or hit an error in the dialog / Terminal window. Ask what was reported:
- `che-keychain` returned exit code `2` → user cancelled. Just re-run from Step 4.
- `verification failed: ... HTTP 401` → key pair was wrong or mis-copied (trailing space, swapped id/secret). Re-run from Step 4; double-check against the TDX 編輯 page.
- The user closed the dialog / Terminal early → just re-run Step 4.

## Step 7: Restart Claude Code

Even after credentials verify, the MCP server already spawned by the current Claude Code session won't see them. The user must **fully quit Claude Code (Cmd+Q)** and reopen. Closing the window is not enough — MCP server processes outlive a closed window.

## Fallback: no Terminal.app available

If `open -a Terminal` is unavailable (SSH session, headless), tell the user to run the binary's `--setup` directly in whatever interactive shell they have. Emphasize: run it in a **terminal, not in Claude Code chat** — the secret prompt needs a TTY.

```bash
~/bin/CheTransportMCP --setup
```

Same interactive flow, no shell-script middleman. If the binary isn't at `~/bin/CheTransportMCP` yet, run the wrapper instead (it downloads then forwards):

```bash
~/.claude/plugins/cache/*/che-transport-mcp/*/bin/che-transport-mcp-wrapper.sh --setup
```

## When NOT to invoke this skill

- User reports tools returning empty arrays `{"matches": [], "trains": []}` — that's "empty ≠ error" by design, not a credential issue
- User reports `429 rate limit` — credentials are fine, slow down request rate
- User reports `Invalid station '...'` — credentials are fine, query format wrong (use `rail_search_stations` first to get IDs)
