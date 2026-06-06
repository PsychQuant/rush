## Summary

Rename and rebrand the already-self-contained che-transport-mcp product repo to "Rush" — a systematic identifier rename across the GitHub repo, the built binary, the plugin, the self-marketplace catalog, and external references — with no change to routing behavior, the 27-tool surface, or stored TDX credentials.

## Motivation

The project has outgrown its original framing as "a transport MCP": it now hosts a time-dependent multimodal routing core (RaptorCore), an in-progress bus-ETA capture subsystem, and an explicit north-star goal of a Taiwan-wide NAVITIME-class router. The repository is already self-contained — it holds the Swift MCP binary source, the Claude Code plugin shell, and its own marketplace catalog in one place. What is missing is a product identity. Rebranding to "Rush" graduates it from a descriptively-named MCP into a named product and makes the self-marketplace the canonical distribution unit.

## Proposed Solution

Perform a systematic identifier rename, leaving behavior untouched:

1. Rename the GitHub repository from che-transport-mcp to rush. Rely on GitHub automatic redirect of the old repository, release, and clone URLs during the transition while updating every hard reference.
2. Rename the built binary from CheTransportMCP to Rush: the Swift package product and executable target, the source directory under Sources, the test target under Tests, the Makefile, the mcpb build script, and the packed bundle names.
3. Rename the plugin identity from che-transport-mcp to rush in the plugin manifest and in the self-marketplace catalog (marketplace name, plugin name, and descriptions). Keep the in-plugin MCP server key transport so the domain stays stable.
4. Replace the binary wrapper script with a rush-named wrapper that downloads the Rush binary from the renamed repository releases (release-pinned with the sha256 sidecar, same mechanism as today).
5. Preserve the keychain service identifier che-transport-tdx exactly, so TDX credentials already configured on the laptop and the mini keep working without re-setup.
6. Update external references: the central psychquant-claude-plugins marketplace entry (which currently still lists che-transport-mcp with stale metadata), the che-mcps umbrella reference, and the top-level CLAUDE and README files.
7. Bump the plugin version and binaryVersion to mark the rebranded release, and document the migration path for existing installs (the plugin name changes, so existing users reinstall under the new name rather than auto-upgrade).

## Non-Goals

- No change to the 27 MCP tools names, inputs, outputs, or routing behavior. This is packaging, branding, and distribution only.
- No change to the keychain service identifier che-transport-tdx. Existing TDX credentials MUST keep working.
- No change to the in-progress bus-eta-logger subsystem.
- Not selecting an alternative product name. "Rush" is chosen knowingly despite overlapping with Microsoft Rush (rushjs.org); the owner accepts the collision as low-stakes for a personal-marketplace plugin.

## Alternatives Considered

- Keep the descriptive name and the split three-repo distribution (separate binary repo plus a central marketplace shell). Rejected: the repo is already self-contained and the goal is a single branded product unit.
- Pick a more distinctive name to avoid the Microsoft Rush overlap. Considered and declined by the owner.

## Impact

- Affected specs: rush-distribution (new capability)
- Affected code:
  - Modified: Package.swift, Makefile, scripts/build-mcpb.sh, CLAUDE.md, README.md, README_zh-TW.md, .claude-plugin/marketplace.json, plugin/.claude-plugin/plugin.json, plugin/.mcp.json, plugin/README.md, plugin/CLAUDE.md, plugin/hooks/session-start.sh, plugin/tests/test-session-start.sh, plugin/skills/setup-tdx/SKILL.md
  - New: plugin/bin/rush-wrapper.sh
  - Removed: plugin/bin/che-transport-mcp-wrapper.sh
  - Renamed directories: Sources/CheTransportMCP to Sources/Rush, Tests/CheTransportMCPTests to Tests/RushTests
- Cross-repo (prose, not in this repo tree): the GitHub repository name; the central psychquant-claude-plugins marketplace entry plus its plugins/che-transport-mcp shell; the che-mcps umbrella reference and the umbrella CLAUDE submodule table.
