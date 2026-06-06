## ADDED Requirements

### Requirement: Unified Rush Product Identity
The GitHub repository, the built binary, the Claude Code plugin, and the self-marketplace catalog SHALL all use the "Rush" product identity: repository rush, binary Rush, plugin name rush, marketplace name rush.

#### Scenario: Built artifacts carry the Rush identity
- **WHEN** the Swift package is built and the mcpb bundle is packed
- **THEN** the produced executable is named Rush and the bundle uses the rush prefix
- **AND** the plugin manifest and the marketplace catalog declare the name rush

### Requirement: Preserved Credential Service
The Rush binary SHALL read TDX credentials from the keychain service identifier che-transport-tdx, unchanged from before the rename.

#### Scenario: Pre-rename credentials still authenticate
- **WHEN** TDX credentials were stored under service che-transport-tdx before the rename
- **AND** the renamed Rush binary performs an OAuth token request
- **THEN** it reads those credentials and authenticates successfully without re-setup

### Requirement: Preserved Tool Surface
The rename SHALL NOT change the 27 MCP tools: their names, inputs, outputs, and routing behavior remain identical, and the in-plugin MCP server key remains transport.

#### Scenario: Tool surface unchanged after rename
- **WHEN** the Rush plugin is loaded
- **THEN** the same 27 tools are exposed with the same names and parameters as before the rename
- **AND** the in-plugin MCP server key is transport

### Requirement: Self-Marketplace Distribution
The repository SHALL function as its own plugin marketplace named rush; adding the repository as a marketplace and installing the rush plugin SHALL load the tools.

#### Scenario: Fresh self-marketplace install
- **WHEN** a user adds the rush repository as a Claude Code marketplace and installs the rush plugin
- **THEN** the wrapper downloads the Rush binary and the 27 tools load

### Requirement: Release-Pinned Binary Auto-Download
The plugin wrapper SHALL download the Rush release asset from the renamed repository releases, pinned to the declared binaryVersion via a version sidecar, installing it with an atomic temp-file swap so a partial download never replaces a working binary. A sha256 sidecar SHALL be published alongside each release for verification.

#### Scenario: Wrapper fetches the pinned Rush asset
- **WHEN** the plugin wrapper runs and the pinned Rush binary is not present locally
- **THEN** it downloads the Rush asset for the pinned binaryVersion from the rush repository releases and installs it via an atomic temp-file swap
- **AND** the release publishes a matching sha256 sidecar alongside the Rush asset

### Requirement: Documented Migration for Existing Installs
Because the plugin name changes from che-transport-mcp to rush, existing installs SHALL be migrated by reinstall under the new name with user-facing documentation; the rename SHALL NOT silently auto-upgrade across the name change.

#### Scenario: Existing user migrates
- **WHEN** a user previously installed che-transport-mcp
- **THEN** the migration documentation directs them to uninstall che-transport-mcp and install rush
- **AND** after reinstall the wrapper auto-downloads the Rush binary and credentials under che-transport-tdx continue to work
