## Context

The repository is already self-contained: it holds the Swift MCP binary source (Sources/CheTransportMCP, product CheTransportMCP), the Claude Code plugin shell (plugin/), and its own marketplace catalog (.claude-plugin/marketplace.json). It is ALSO listed in the central psychquant-claude-plugins marketplace (entry name che-transport-mcp, source ./plugins/che-transport-mcp, with stale metadata: binaryVersion 0.2.2, "23 tools", references removed Maritime). This change is a systematic identifier rename to the product name "Rush", not a structural change.

## Goals

- One consistent product identity "Rush" across repo, binary, plugin, and marketplace.
- Zero change to routing behavior, the 27-tool surface, and stored TDX credentials.
- Existing self-marketplace install path keeps working; existing central-marketplace users get a documented migration.

## Non-Goals

- Routing/tool behavior changes; keychain service rename; bus-eta-logger changes (separate change).

## Rename Map (the core contract)

| Domain | From | To |
|--------|------|----|
| GitHub repo | PsychQuant/che-transport-mcp | PsychQuant/rush |
| Swift product + executable target | CheTransportMCP | Rush |
| Source directory | Sources/CheTransportMCP | Sources/Rush |
| Test target + directory | CheTransportMCPTests / Tests/CheTransportMCPTests | RushTests / Tests/RushTests |
| Plugin name (plugin.json) | che-transport-mcp | rush |
| Marketplace name + plugin entry (.claude-plugin/marketplace.json) | che-transport-mcp | rush |
| Wrapper script | plugin/bin/che-transport-mcp-wrapper.sh | plugin/bin/rush-wrapper.sh |
| Release asset name | CheTransportMCP | Rush |
| mcpb bundle prefix (new builds) | che-transport-mcp-X.Y.Z | rush-X.Y.Z |

## Preserved Invariants (MUST NOT change)

- Keychain service identifier: che-transport-tdx (Sources/CheTransportMCP/Auth.swift defaultService). The renamed Rush binary continues to read che-transport-tdx so credentials already set on the laptop and the mini keep working.
- In-plugin MCP server key in plugin/.mcp.json: transport (kept stable as the domain segment).
- The 27 MCP tool names, inputs, outputs, routing behavior, 3-tier cache TTL, and NSQL confirmation discipline.
- Historical mcpb bundles already in mcpb/ are left untouched (they record past releases).

## Decisions

- D1 Version: bump plugin.json version and binaryVersion to 1.0.0 to mark the Rush 1.0 product launch (behavior unchanged, but the plugin identity changes so a clean major is the launch marker).
- D2 Central marketplace: update the central psychquant-claude-plugins entry and its plugins/che-transport-mcp shell copy to rush (rename + correct the stale metadata to match the current 27-tool reality), keeping it in sync with the self-marketplace; the self-marketplace in this repo remains canonical. This avoids orphaning users who installed via the central marketplace.
- D3 Migration: because the plugin name changes, Claude Code treats rush as a new plugin (no silent auto-upgrade across a name change). Document a migration note: existing users uninstall che-transport-mcp and install rush; the wrapper then auto-downloads the Rush binary.
- D4 GitHub redirect: rely on GitHub automatic redirect for transitional URL compatibility, but update every hard reference in this change so nothing depends on the redirect long-term.

## Implementation Sequence

1. In-repo identifier rename on a branch: Package.swift (product, executable target, test target), Sources directory, Tests directory, Makefile, scripts/build-mcpb.sh, the plugin shell (plugin.json, .mcp.json keeping server key transport, wrapper script renamed, hooks/session-start.sh, tests, setup-tdx skill), .claude-plugin/marketplace.json, top-level CLAUDE.md + README.md + README_zh-TW.md.
2. Point the new rush-wrapper.sh download at the PsychQuant/rush releases path for the Rush asset (release-pinned, sha256 sidecar mechanism unchanged).
3. Build + run tests under the new target name to confirm the rename is internally consistent.
4. Rename the GitHub repository to rush (via gh repo rename, owner-driven), so releases land on the renamed repo.
5. Run the sign + notarize + release pipeline to publish the Rush 1.0.0 binary + sha256 + mcpb to the renamed repo releases.
6. Update the central psychquant-claude-plugins entry + shell copy to rush and sync the marketplace.
7. Update the che-mcps umbrella reference and umbrella CLAUDE submodule table.
8. Verify a clean install from the self-marketplace pulls the Rush binary and the 27 tools load.

## Risks

- Release ordering: the wrapper points at PsychQuant/rush releases, so the repo rename (step 4) must precede the first Rush release (step 5); until then the wrapper has nothing to download. Mitigation: follow the sequence; GitHub redirect covers the transition window for old URLs.
- Existing installs break on the name change (expected, per D3). Mitigation: migration note in README and the central marketplace description.
- Keychain mismatch confusion: the Rush binary reading che-transport-tdx is intentional and documented in the design and CLAUDE.md.

## Implementation Contract

- After this change, building the package produces a binary named Rush; the plugin and self-marketplace are named rush; the wrapper downloads the Rush asset from the renamed repo; the keychain service che-transport-tdx and all 27 tool names/behaviors are unchanged; a fresh self-marketplace install loads the 27 tools and TDX credentials configured before the rename still authenticate.
