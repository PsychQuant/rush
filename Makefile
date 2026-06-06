# Makefile
BINARY_NAME := Rush

.PHONY: build test setup-tdx check-auth release release-signed verify-release-ready install clean

build:
	swift build

test:
	swift test

setup-tdx: build
	@.build/debug/Rush --setup

check-auth: build
	@.build/debug/Rush --check-auth

# Soft pre-flight: warn (not fail) on drift between AppVersion.version and the
# latest git tag. Pre-release work expects version to be ahead of tag; this
# target makes the state visible so maintainer can decide whether to bump or tag.
verify-release-ready:
	@SOURCE_VERSION=$$(grep -E 'static let version = "' Sources/Rush/Version.swift | sed -E 's/.*"([^"]+)".*/\1/'); \
	LATEST_TAG=$$(git tag --sort=-creatordate | head -1); \
	if [ -z "$$SOURCE_VERSION" ]; then \
	    echo "✗ Could not parse AppVersion.version from Version.swift" >&2; \
	    echo "  This target must be run from the repo root." >&2; \
	    exit 1; \
	fi; \
	if [ -z "$$LATEST_TAG" ]; then \
	    echo "ℹ No git tags yet — version drift check skipped (first release?)"; \
	elif [ "v$${SOURCE_VERSION}" = "$$LATEST_TAG" ]; then \
	    echo "ℹ AppVersion.version ($$SOURCE_VERSION) matches latest tag ($$LATEST_TAG) — no bump needed"; \
	elif [ "$$(printf '%s\n%s\n' "v$${SOURCE_VERSION}" "$$LATEST_TAG" | sort -V | tail -1)" = "v$${SOURCE_VERSION}" ]; then \
	    echo "⚠ Pre-release drift: AppVersion.version=$$SOURCE_VERSION is AHEAD of latest tag=$$LATEST_TAG"; \
	    echo "  Expected if you're cutting v$${SOURCE_VERSION}. Tag v$${SOURCE_VERSION} when this build ships."; \
	else \
	    echo "⚠ DOWNGRADE drift: AppVersion.version=$$SOURCE_VERSION is BEHIND latest tag=$$LATEST_TAG"; \
	    echo "  DO NOT tag v$${SOURCE_VERSION} — that would publish older code as the latest release."; \
	    echo "  Likely cause: stale branch, bad merge, or accidental Version.swift revert. Investigate before continuing."; \
	fi

# Local release build (ad-hoc signed). Use for dev iteration, NOT for distribution.
release:
	@./scripts/build-mcpb.sh

# Distribution release: builds universal binary, signs with Developer ID,
# notarizes via xcrun notarytool, and packages into .mcpb.
# Requires Developer ID Application cert in keychain + notarytool keychain
# profile (see README "Signing & Notarization" for one-time setup).
#
# Must be run from the repo root: ./scripts/build-mcpb.sh uses relative paths.
release-signed: verify-release-ready
	@: $${DEVELOPER_ID:?DEVELOPER_ID not set. See README 'Signing & Notarization' for setup.}
	@: $${NOTARY_PROFILE:?NOTARY_PROFILE not set. See README 'Signing & Notarization' for setup.}
	REQUIRE_CODESIGN=1 ./scripts/build-mcpb.sh

# Local dev install (ad-hoc signed). No TCC interaction needed for this MCP
# (TDX is plain HTTPS), so ad-hoc is fine for dev iteration.
install: release
	mkdir -p ~/bin
	rm -f ~/bin/$(BINARY_NAME)
	cp mcpb/server/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	@echo "Installed: ~/bin/$(BINARY_NAME)"

clean:
	swift package clean
	rm -rf .build mcpb/server mcpb/*.mcpb mcpb/*.mcpb.sha256
