// Sources/CheTransportMCP/ToolRegistry.swift
import Foundation
import MCP

/// Aggregates MCP `Tool` definitions and per-name dispatch handlers across
/// transport-mode modules (Rail / Bus / Bike / Air / Traffic / Parking).
///
/// The MCP swift-sdk allows only **one** `withMethodHandler(ListTools.self)` and
/// **one** `withMethodHandler(CallTool.self)` per `Server`; later calls overwrite
/// earlier ones. So each mode module appends into a shared `ToolRegistry`, and
/// `Server.swift` installs the two handlers exactly once — both delegating to
/// this actor.
actor ToolRegistry {
    typealias Dispatcher = (String, [String: Value]) async -> CallTool.Result

    private var tools: [Tool] = []
    /// Each handler is a closure that already knows which dispatcher to call;
    /// keying by tool name keeps lookup O(1).
    private var handlers: [String: ([String: Value]) async -> CallTool.Result] = [:]

    /// Register a batch of tools that share a single dispatcher (switch-by-name pattern).
    func register(tools newTools: [Tool], dispatch: @escaping Dispatcher) {
        for tool in newTools {
            tools.append(tool)
            let name = tool.name
            handlers[name] = { args in await dispatch(name, args) }
        }
    }

    func allTools() -> [Tool] { tools }

    func count() -> Int { tools.count }

    func handleCall(name: String, arguments: [String: Value]) async -> CallTool.Result {
        if let handler = handlers[name] {
            return await handler(arguments)
        }
        return CallTool.Result(
            content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}
