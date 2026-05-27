#!/bin/bash
# SessionStart hook — emit single-line status banner for che-transport-mcp.
# Shows binary version (from sidecar) + whether TDX credentials are seeded.

set -u

BINARY_NAME="CheTransportMCP"
VERSION_FILE="$HOME/bin/.${BINARY_NAME}.version"
BINARY="$HOME/bin/$BINARY_NAME"

if [[ -x "$BINARY" ]]; then
    VERSION="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || echo 'unknown')"
    echo "✓ $BINARY_NAME v${VERSION} installed: $BINARY"
else
    echo "ℹ $BINARY_NAME not installed — will auto-download on first MCP call"
fi

# Surface TDX credential status. Keychain account names match the Auth.swift
# convention (service=che-transport-tdx). We don't print the secret — just
# whether the keychain entry exists. Soft-fail: missing creds is not a fatal
# state, it just means /setup-tdx hasn't been run yet.
if security find-generic-password -s che-transport-tdx -a client_id >/dev/null 2>&1 \
   && security find-generic-password -s che-transport-tdx -a client_secret >/dev/null 2>&1; then
    echo "✓ TDX credentials present in keychain (service: che-transport-tdx)"
else
    echo "⚠ TDX credentials missing — run /che-transport-mcp:setup-tdx or \`make setup-tdx\` in source repo"
    echo "   register free TDX account: https://tdx.transportdata.tw/register"
fi
