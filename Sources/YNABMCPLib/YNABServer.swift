import Foundation
import MCP

public func startServer(client: YNABClient) async throws {
    let server = Server(
        name: "ynab-mcp",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
    )

    // Register handlers before starting so they're ready when the client connects
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: ToolHandlers.allTools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        await ToolHandlers.handleCall(
            name: params.name,
            arguments: params.arguments,
            client: client
        )
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)

    log("YNAB MCP server started")
    await server.waitUntilCompleted()
}

/// Log to stderr (stdout is reserved for JSON-RPC protocol)
public func log(_ message: String) {
    FileHandle.standardError.write(Data("[ynab-mcp] \(message)\n".utf8))
}
