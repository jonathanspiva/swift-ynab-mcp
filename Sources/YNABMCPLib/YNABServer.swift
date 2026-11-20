import Foundation
import MCP

public enum ServerInfo {
    public static let name = "ynab-mcp"
    public static let version = "2.1.0"

    /// Sent to the client at initialize time; Claude Code shows this to the model alongside the tools.
    public static func instructions(readOnly: Bool, defaultPlanId: String) -> String {
        var text = """
        Tools for a YNAB (You Need A Budget) account.

        - Every tool takes an optional plan_id. When omitted it uses `\(defaultPlanId)`. Call list_plans only if the user has several plans.
        - Amounts in and out are in the plan's currency units (e.g. -42.50), not YNAB milliunits. Negative is an outflow.
        - Dates are YYYY-MM-DD. Months are YYYY-MM-01 or 'current'.
        - Look up IDs with list_accounts, list_categories, and list_payees before writing.
        - YNAB allows 200 API requests per hour. Prefer one bulk_update_transactions call over many update_transaction calls, and use date ranges and filters instead of paging through history.
        - For spending questions use spending_report or monthly_trends rather than summing list_transactions output yourself.
        """
        if readOnly {
            text += "\n- This server is read-only (YNAB_READ_ONLY is set). Write tools are unavailable."
        } else {
            text += "\n- Write tools change the user's live budget. Confirm intent before bulk or ambiguous changes."
        }
        return text
    }
}

public struct ServerConfig: Sendable {
    public var token: String
    public var defaultPlanId: String
    public var readOnly: Bool

    /// Read configuration from the environment. Returns nil when YNAB_TOKEN is missing.
    public init?(environment: [String: String]) {
        guard let token = environment["YNAB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        self.token = token
        let plan = environment["YNAB_PLAN_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.defaultPlanId = plan.isEmpty ? "last-used" : plan
        self.readOnly = Self.isTruthy(environment["YNAB_READ_ONLY"])
    }

    static func isTruthy(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(value)
    }
}

public func startServer(config: ServerConfig) async throws {
    let client = YNABClient(
        accessToken: config.token,
        rateLimiter: RateLimiter(),
        defaultPlanId: config.defaultPlanId
    )
    let server = Server(
        name: ServerInfo.name,
        version: ServerInfo.version,
        instructions: ServerInfo.instructions(readOnly: config.readOnly, defaultPlanId: config.defaultPlanId),
        capabilities: .init(tools: .init(listChanged: false))
    )

    // Register handlers before starting so they're ready when the client connects.
    let tools = ToolHandlers.tools(readOnly: config.readOnly)
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: tools)
    }
    await server.withMethodHandler(CallTool.self) { params in
        await ToolHandlers.handleCall(
            name: params.name,
            arguments: params.arguments,
            client: client,
            readOnly: config.readOnly
        )
    }

    try await server.start(transport: StdioTransport())
    log("started v\(ServerInfo.version) (\(config.readOnly ? "read-only" : "read-write"), \(tools.count) tools)")
    await server.waitUntilCompleted()
}

/// Log to stderr (stdout is reserved for JSON-RPC).
public func log(_ message: String) {
    FileHandle.standardError.write(Data("[ynab-mcp] \(message)\n".utf8))
}
