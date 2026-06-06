// Sources/Rush/Version.swift
import Foundation

enum AppVersion {
    static let version = "1.0.0"
    static let versionString = "Rush \(version)"
    static let helpMessage = """
    \(versionString)

    USAGE:
      Rush                 Run MCP server on stdio
      Rush --version       Print version
      Rush --help          Print this help
      Rush --setup         Interactively store TDX credentials in keychain
      Rush --check-auth    Verify TDX credentials in keychain

    SETUP:
      Run `Rush --setup` once to register TDX credentials.
    """
}
