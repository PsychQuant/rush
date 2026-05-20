# Makefile
.PHONY: build test setup-tdx check-auth clean

build:
	swift build

test:
	swift test

setup-tdx:
	@bash scripts/setup-tdx.sh

check-auth: build
	@.build/debug/CheTransportMCP --check-auth

clean:
	swift package clean
	rm -rf .build
