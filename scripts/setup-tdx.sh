#!/usr/bin/env bash
# scripts/setup-tdx.sh
set -euo pipefail

SERVICE="che-transport-tdx"

echo "TDX credentials setup for che-transport-mcp"
echo "Register first at: https://tdx.transportdata.tw/register"
echo ""

read -p "TDX client_id: " CLIENT_ID
read -s -p "TDX client_secret: " CLIENT_SECRET
echo ""

# Save to keychain via the binary
BIN="${BIN:-.build/debug/CheTransportMCP}"
if [ ! -x "$BIN" ]; then
    echo "Building debug binary..."
    swift build
fi

# Save credentials by invoking a helper subcommand we'll add; for now use security directly.
security delete-generic-password -s "$SERVICE" -a "client_id" 2>/dev/null || true
security delete-generic-password -s "$SERVICE" -a "client_secret" 2>/dev/null || true
security add-generic-password -s "$SERVICE" -a "client_id" -w "$CLIENT_ID" -U
security add-generic-password -s "$SERVICE" -a "client_secret" -w "$CLIENT_SECRET" -U

echo ""
echo "Verifying credentials by hitting TDX..."
if "$BIN" --check-auth; then
    echo "Setup complete."
else
    echo "Setup failed verification. Check credentials and retry."
    exit 1
fi
