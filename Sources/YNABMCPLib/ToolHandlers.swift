import Foundation
import MCP
import SwiftYNAB

public enum ToolHandlers {

    // MARK: - All Tools

    public static let allTools: [Tool] = [
        // Read tools
        listBudgetsTool,
        listAccountsTool,
        listCategoriesTool,
        getBudgetSummaryTool,
        listRecentTransactionsTool,
        getMonthSummaryTool,
        getTransactionTool,
        listPayeesTool,
        getTransactionsByPayeeTool,
        getTransactionsByCategoryTool,
        listScheduledTransactionsTool,
        // Write tools
        createTransactionTool,
        updateTransactionTool,
        bulkUpdateTransactionsTool,
        renamePayeeTool,
        updateCategoryBudgetTool,
    ]

    // MARK: - Call Routing

    public static func handleCall(
        name: String,
        arguments: [String: Value]?,
        client: YNABClient
    ) async -> CallTool.Result {
        do {
            let args = arguments ?? [:]
            switch name {
            // Read tools
            case "list_budgets":
                return try await handleListBudgets(client: client)
            case "list_accounts":
                return try await handleListAccounts(args: args, client: client)
            case "list_categories":
                return try await handleListCategories(args: args, client: client)
            case "get_budget_summary":
                return try await handleGetBudgetSummary(args: args, client: client)
            case "list_recent_transactions":
                return try await handleListRecentTransactions(args: args, client: client)
            case "get_month_summary":
                return try await handleGetMonthSummary(args: args, client: client)
            case "get_transaction":
                return try await handleGetTransaction(args: args, client: client)
            case "list_payees":
                return try await handleListPayees(args: args, client: client)
            case "get_transactions_by_payee":
                return try await handleGetTransactionsByPayee(args: args, client: client)
            case "get_transactions_by_category":
                return try await handleGetTransactionsByCategory(args: args, client: client)
            case "list_scheduled_transactions":
                return try await handleListScheduledTransactions(args: args, client: client)
            // Write tools
            case "create_transaction":
                return try await handleCreateTransaction(args: args, client: client)
            case "update_transaction":
                return try await handleUpdateTransaction(args: args, client: client)
            case "bulk_update_transactions":
                return try await handleBulkUpdateTransactions(args: args, client: client)
            case "rename_payee":
                return try await handleRenamePayee(args: args, client: client)
            case "update_category_budget":
                return try await handleUpdateCategoryBudget(args: args, client: client)
            default:
                return CallTool.Result(
                    content: [.text("Unknown tool: \(name)")],
                    isError: true
                )
            }
        } catch {
            return CallTool.Result(
                content: [.text("Error: \(error)")],
                isError: true
            )
        }
    }

    // MARK: - Parameter Helpers

    public static func requireString(_ args: [String: Value], key: String) throws -> String {
        guard let value = args[key]?.stringValue else {
            throw YNABMCPError.missingParameter(key)
        }
        return value
    }

    public static func requireDouble(_ args: [String: Value], key: String) throws -> Double {
        if let d = args[key]?.doubleValue {
            return d
        }
        if let i = args[key]?.intValue {
            return Double(i)
        }
        throw YNABMCPError.missingParameter(key)
    }

    public static func requireStringArray(_ args: [String: Value], key: String) throws -> [String] {
        guard let arrayValue = args[key]?.arrayValue else {
            throw YNABMCPError.missingParameter(key)
        }
        let strings = arrayValue.compactMap(\.stringValue)
        guard !strings.isEmpty else {
            throw YNABMCPError.invalidParameter(key, detail: "Array must contain at least one string")
        }
        return strings
    }

    public static func parseFlagColor(_ string: String?) -> FlagColor? {
        guard let string else { return nil }
        switch string.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "none", "": return FlagColor.none
        default: return nil
        }
    }

    public static func parseClearedStatus(_ string: String?) -> ClearedStatus? {
        guard let string else { return nil }
        switch string.lowercased() {
        case "cleared": return .cleared
        case "reconciled": return .reconciled
        case "uncleared": return .uncleared
        default: return nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return dateFormatter.date(from: string)
    }
}
