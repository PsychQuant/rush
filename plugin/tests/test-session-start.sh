#!/usr/bin/env bash
# Behavior test for plugin/hooks/session-start.sh — the binary-presence
# banner branch. Pure bash, no framework dependency.
#
# Scope: only the binary-presence half is asserted (driven by a HOME
# override pointing at a temp dir with / without a fake binary). The TDX
# credential half calls `security` against the real keychain and is left
# unasserted — testing its "present" branch would require seeding the
# keychain, which is out of scope for a hook smoke test.
#
# Run: bash plugin/tests/test-session-start.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/session-start.sh"
failures=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "ok   - $label"
    else
        echo "FAIL - $label"
        echo "       expected to contain: $needle"
        echo "       got: $haystack"
        failures=$((failures + 1))
    fi
}

# Case 1: binary present + sidecar → "✓ … vX installed".
tmp_present="$(mktemp -d)"
mkdir -p "$tmp_present/bin"
printf '#!/bin/sh\n' > "$tmp_present/bin/CheTransportMCP"
chmod +x "$tmp_present/bin/CheTransportMCP"
echo "0.2.2" > "$tmp_present/bin/.CheTransportMCP.version"
out_present="$(HOME="$tmp_present" bash "$HOOK" 2>&1)"
assert_contains "$out_present" "✓ CheTransportMCP v0.2.2 installed" "binary present → installed banner"
rm -rf "$tmp_present"

# Case 2: empty HOME → "… not installed".
tmp_absent="$(mktemp -d)"
out_absent="$(HOME="$tmp_absent" bash "$HOOK" 2>&1)"
assert_contains "$out_absent" "not installed" "binary absent → not-installed banner"
rm -rf "$tmp_absent"

if [[ $failures -eq 0 ]]; then
    echo "All session-start hook tests passed."
    exit 0
else
    echo "$failures test(s) failed."
    exit 1
fi
