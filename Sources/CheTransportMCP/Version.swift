// Sources/CheTransportMCP/Version.swift
import Foundation

enum AppVersion {
    static let version = "0.1.0"
    static let versionString = "CheTransportMCP \(version)"
    static let helpMessage = """
    \(versionString)

    USAGE:
      CheTransportMCP                 Run MCP server on stdio
      CheTransportMCP --version       Print version
      CheTransportMCP --help          Print this help
      CheTransportMCP --check-auth    Verify TDX credentials in keychain

    SETUP:
      Run `make setup-tdx` once to register TDX credentials.
    """
}
