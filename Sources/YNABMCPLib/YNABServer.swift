import Foundation
import MCP

public func startServer(client: YNABClient) async throws {
    let server = Server(
        name: "ynab-mcp",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
    )

    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Register tool listing handler
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: ToolHandlers.allTools)
    }

    // Register tool call handler
    await server.withMethodHandler(CallTool.self) { params in
        await ToolHandlers.handleCall(
            name: params.name,
            arguments: params.arguments,
            client: client
        )
    }

    log("YNAB MCP server started")
    await server.waitUntilCompleted()
}

/// Log to stderr (stdout is reserved for JSON-RPC protocol)
public func log(_ message: String) {
    FileHandle.standardError.write(Data("[ynab-mcp] \(message)\n".utf8))
}
