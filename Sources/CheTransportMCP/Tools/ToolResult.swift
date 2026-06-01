// Sources/CheTransportMCP/Tools/ToolResult.swift
import Foundation
import MCP

/// Single serialization point for every tool's JSON response.
///
/// Previously each tool module carried its own byte-identical `jsonResult` /
/// `resultJSON` / `routeResult` helper (plus two inline copies in `RailTools`),
/// so wiring `JSONSanitize.clean` into the path in #1 meant editing eight places.
/// Centralizing here keeps the sanitize call in exactly one location.
enum ToolResult {
    /// Serialize `obj` to a JSON `CallTool.Result`, running it through
    /// ``JSONSanitize/clean(_:)`` first so `Double`s emit their shortest
    /// round-trippable form. Falls back to `{}` if serialization fails.
    static func json(_ obj: [String: Any]) -> CallTool.Result {
        let data = (try? JSONSerialization.data(withJSONObject: JSONSanitize.clean(obj))) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}
