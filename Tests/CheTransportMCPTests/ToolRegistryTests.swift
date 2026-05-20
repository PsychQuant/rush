import XCTest
import MCP
@testable import CheTransportMCP

final class ToolRegistryTests: XCTestCase {
    func testRegisterAccumulatesTools() async {
        let registry = ToolRegistry()
        let toolA = Tool(name: "a", description: "", inputSchema: .object([:]), annotations: nil)
        let toolB = Tool(name: "b", description: "", inputSchema: .object([:]), annotations: nil)

        await registry.register(tools: [toolA]) { _, _ in
            CallTool.Result(content: [.text(text: "a", annotations: nil, _meta: nil)])
        }
        await registry.register(tools: [toolB]) { _, _ in
            CallTool.Result(content: [.text(text: "b", annotations: nil, _meta: nil)])
        }

        let count = await registry.count()
        XCTAssertEqual(count, 2, "two registrations should coexist (no overwrite)")
        let names = await registry.allTools().map(\.name)
        XCTAssertEqual(names, ["a", "b"])
    }

    func testHandleCallRoutesByName() async {
        let registry = ToolRegistry()
        let tools = [
            Tool(name: "echo", description: "", inputSchema: .object([:]), annotations: nil),
            Tool(name: "ping", description: "", inputSchema: .object([:]), annotations: nil)
        ]
        await registry.register(tools: tools) { name, _ in
            CallTool.Result(content: [.text(text: name, annotations: nil, _meta: nil)])
        }

        let echoResult = await registry.handleCall(name: "echo", arguments: [:])
        XCTAssertEqual(textBody(echoResult), "echo")
        let pingResult = await registry.handleCall(name: "ping", arguments: [:])
        XCTAssertEqual(textBody(pingResult), "ping")
    }

    func testHandleCallUnknownToolReturnsError() async {
        let registry = ToolRegistry()
        await registry.register(tools: [Tool(name: "known", description: "", inputSchema: .object([:]), annotations: nil)]) { _, _ in
            CallTool.Result(content: [])
        }

        let result = await registry.handleCall(name: "unknown", arguments: [:])
        XCTAssertEqual(result.isError, true, "unknown tool must surface as MCP error")
        XCTAssertTrue(textBody(result)?.contains("Unknown tool: unknown") == true)
    }

    // MARK: - helpers

    private func textBody(_ result: CallTool.Result) -> String? {
        for content in result.content {
            if case .text(let text, _, _) = content { return text }
        }
        return nil
    }
}
