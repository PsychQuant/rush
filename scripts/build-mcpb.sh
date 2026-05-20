#!/usr/bin/env bash
# scripts/build-mcpb.sh
# Build + (optionally) sign + (optionally) notarize + package CheTransportMCP into a .mcpb.
#
# Modes:
#   default                                — universal binary + ad-hoc sign + pack
#   REQUIRE_CODESIGN=1                     — fail-fast if Developer ID or notary profile missing;
#                                            sign with Developer ID and notarize via xcrun notarytool
#
# Required env vars when REQUIRE_CODESIGN=1:
#   DEVELOPER_ID         — Developer ID Application cert SHA-1 fingerprint (40-hex)
#   NOTARY_PROFILE       — keychain profile name (see README "Signing & Notarization")
#
# Output:
#   mcpb/server/CheTransportMCP         — universal binary (arm64 + x86_64)
#   mcpb/server/CheTransportMCP.sha256  — hash file for --self-update integrity check
#   mcpb/che-transport-mcp-<version>.mcpb        — Claude Desktop one-click bundle
#   mcpb/che-transport-mcp-<version>.mcpb.sha256 — bundle hash

set -euo pipefail

BINARY_NAME="CheTransportMCP"
PLUGIN_NAME="che-transport-mcp"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MCPB_DIR="$REPO_ROOT/mcpb"
SERVER_DIR="$MCPB_DIR/server"

# Step 0: parse version from source. AppVersion.current is the single source of truth.
SOURCE_VERSION=$(grep -E 'static let version = "' "$REPO_ROOT/Sources/CheTransportMCP/Version.swift" | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$SOURCE_VERSION" ]]; then
    echo "✗ Could not parse AppVersion.version from Version.swift" >&2
    exit 1
fi
echo "→ Building $PLUGIN_NAME v$SOURCE_VERSION"

# Step 0.5: sanity-check that mcpb/manifest.json version matches Source. Drift here means
# end users see one version in the install dialog but another in --version output.
MANIFEST_VERSION=$(grep -E '"version"' "$MCPB_DIR/manifest.json" | head -1 | sed -E 's/.*"version"[^"]*"([^"]+)".*/\1/')
if [[ "$SOURCE_VERSION" != "$MANIFEST_VERSION" ]]; then
    echo "✗ Version drift: Version.swift=$SOURCE_VERSION but mcpb/manifest.json=$MANIFEST_VERSION" >&2
    echo "  Update mcpb/manifest.json before running release." >&2
    exit 1
fi

# Step 1: build universal binary (arm64 + x86_64).
echo "→ Building universal binary"
swift build -c release --arch arm64 --arch x86_64
BUILT_BINARY="$REPO_ROOT/.build/apple/Products/Release/$BINARY_NAME"
if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "✗ Built binary not found at $BUILT_BINARY" >&2
    exit 1
fi

# Step 2: sign.
mkdir -p "$SERVER_DIR"
cp "$BUILT_BINARY" "$SERVER_DIR/$BINARY_NAME"

if [[ "${REQUIRE_CODESIGN:-}" == "1" ]]; then
    : "${DEVELOPER_ID:?DEVELOPER_ID not set (Developer ID Application SHA-1 fingerprint)}"
    : "${NOTARY_PROFILE:?NOTARY_PROFILE not set (notarytool keychain profile name)}"
    echo "→ Signing with Developer ID $DEVELOPER_ID"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$SERVER_DIR/$BINARY_NAME"

    echo "→ Submitting to Apple notarization (this may take 1-15 min)"
    NOTARY_ZIP="$MCPB_DIR/notarize-$BINARY_NAME-$SOURCE_VERSION.zip"
    ditto -c -k --keepParent "$SERVER_DIR/$BINARY_NAME" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    rm -f "$NOTARY_ZIP"

    # Standalone binary cannot be `stapler staple`'d (only bundles/dmg/pkg).
    # Online verification ("first-launch online check") is sufficient for CLI tools.
    echo "✓ Notarized successfully — binary will be validated online on first launch"
else
    echo "→ Ad-hoc signing (dev iteration only; do NOT distribute)"
    codesign --force --sign - "$SERVER_DIR/$BINARY_NAME"
fi

# Step 3: emit hash file for wrapper --self-update integrity check.
HASH=$(shasum -a 256 "$SERVER_DIR/$BINARY_NAME" | awk '{print $1}')
echo "$HASH" > "$SERVER_DIR/$BINARY_NAME.sha256"
echo "  binary sha256: $HASH"

# Step 4: pack .mcpb bundle (zip with .mcpb extension, Claude Desktop convention).
BUNDLE="$MCPB_DIR/$PLUGIN_NAME-$SOURCE_VERSION.mcpb"
rm -f "$BUNDLE" "$BUNDLE.sha256"
( cd "$MCPB_DIR" && zip -qr "$(basename "$BUNDLE")" manifest.json server -x '*.zip' )
BUNDLE_HASH=$(shasum -a 256 "$BUNDLE" | awk '{print $1}')
echo "$BUNDLE_HASH" > "$BUNDLE.sha256"

echo ""
echo "✓ Release artefacts:"
echo "  - $SERVER_DIR/$BINARY_NAME ($HASH)"
echo "  - $BUNDLE ($BUNDLE_HASH)"
echo ""
echo "Next steps for distribution:"
echo "  1. Upload $BUNDLE + $BUNDLE.sha256 to a GitHub release of v$SOURCE_VERSION"
echo "  2. Tag the commit: git tag v$SOURCE_VERSION && git push --tags"
