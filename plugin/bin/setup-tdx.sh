#!/usr/bin/env bash
# setup-tdx.sh — launcher shim. All real logic lives in the Swift binary's
# `--setup` subcommand (interactive prompt + keychain write + OAuth verify).
#
# This file exists only so the setup-tdx skill can `open -a Terminal` a single
# file: `open` cannot pass arguments to a script, so we need a fixed entry
# point that forwards to `wrapper --setup`. The wrapper auto-downloads the
# binary first if it isn't installed yet.
#
# Run interactively in a real Terminal window — the binary's getpass() prompt
# needs a TTY.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/che-transport-mcp-wrapper.sh" --setup
