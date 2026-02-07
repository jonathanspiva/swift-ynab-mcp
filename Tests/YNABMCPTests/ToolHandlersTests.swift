import Foundation
import Testing
import MCP
import SwiftYNAB
@testable import YNABMCPLib

@Suite("ToolHandlers")
struct ToolHandlersTests {

    // MARK: - Tool Definitions

    @Test("All tools are defined")
    func allToolsCount() {
        #expect(ToolHandlers.allTools.count == 16)
    }

    @Test("All tool names use snake_case")
    func toolNamesSnakeCase() {
        for tool in ToolHandlers.allTools {
            #expect(!tool.name.contains("-"), "Tool name '\(tool.name)' should not contain hyphens")
            #expect(!tool.name.contains(" "), "Tool name '\(tool.name)' should not contain spaces")
            #expect(tool.name == tool.name.lowercased(), "Tool name '\(tool.name)' should be lowercase")
        }
    }

    @Test("All tools have descriptions")
    func toolsHaveDescriptions() {
        for tool in ToolHandlers.allTools {
            #expect(tool.description != nil, "Tool '\(tool.name)' should have a description")
            #expect(!(tool.description?.isEmpty ?? true), "Tool '\(tool.name)' description should not be empty")
        }
    }

    @Test("Read tools have readOnlyHint set to true")
    func readToolAnnotations() {
        let readTools = [
            ToolHandlers.listBudgetsTool,
            ToolHandlers.listAccountsTool,
            ToolHandlers.listCategoriesTool,
            ToolHandlers.getBudgetSummaryTool,
            ToolHandlers.listRecentTransactionsTool,
            ToolHandlers.getMonthSummaryTool,
            ToolHandlers.getTransactionTool,
            ToolHandlers.listPayeesTool,
            ToolHandlers.getTransactionsByPayeeTool,
            ToolHandlers.getTransactionsByCategoryTool,
            ToolHandlers.listScheduledTransactionsTool,
        ]
        for tool in readTools {
            #expect(tool.annotations.readOnlyHint == true, "Tool '\(tool.name)' should be read-only")
            #expect(tool.annotations.destructiveHint == false, "Tool '\(tool.name)' should not be destructive")
        }
    }

    @Test("Write tools have readOnlyHint set to false")
    func writeToolAnnotations() {
        let writeTools = [
            ToolHandlers.createTransactionTool,
            ToolHandlers.updateTransactionTool,
            ToolHandlers.bulkUpdateTransactionsTool,
            ToolHandlers.renamePayeeTool,
            ToolHandlers.updateCategoryBudgetTool,
        ]
        for tool in writeTools {
            #expect(tool.annotations.readOnlyHint == false, "Tool '\(tool.name)' should not be read-only")
            #expect(tool.annotations.destructiveHint == false, "Tool '\(tool.name)' should not be destructive")
        }
    }

    @Test("All schemas include type: object")
    func schemasHaveTypeObject() {
        for tool in ToolHandlers.allTools {
            let schema = tool.inputSchema
            if let obj = schema.objectValue {
                #expect(obj["type"]?.stringValue == "object", "Tool '\(tool.name)' schema should have type: object")
            } else {
                Issue.record("Tool '\(tool.name)' inputSchema should be an object")
            }
        }
    }

    @Test("Tool names match expected set")
    func toolNameSet() {
        let names = Set(ToolHandlers.allTools.map(\.name))
        let expected: Set<String> = [
            "list_budgets",
            "list_accounts",
            "list_categories",
            "get_budget_summary",
            "list_recent_transactions",
            "get_month_summary",
            "get_transaction",
            "list_payees",
            "get_transactions_by_payee",
            "get_transactions_by_category",
            "list_scheduled_transactions",
            "create_transaction",
            "update_transaction",
            "bulk_update_transactions",
            "rename_payee",
            "update_category_budget",
        ]
        #expect(names == expected)
    }

    // MARK: - Parameter Helpers

    @Test("requireString extracts string value")
    func requireStringSuccess() throws {
        let args: [String: Value] = ["budget_id": .string("abc-123")]
        let result = try ToolHandlers.requireString(args, key: "budget_id")
        #expect(result == "abc-123")
    }

    @Test("requireString throws on missing key")
    func requireStringMissing() {
        let args: [String: Value] = [:]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireString(args, key: "budget_id")
        }
    }

    @Test("requireString throws on non-string value")
    func requireStringWrongType() {
        let args: [String: Value] = ["budget_id": .int(42)]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireString(args, key: "budget_id")
        }
    }

    @Test("requireDouble extracts double value")
    func requireDoubleSuccess() throws {
        let args: [String: Value] = ["amount": .double(-50.25)]
        let result = try ToolHandlers.requireDouble(args, key: "amount")
        #expect(result == -50.25)
    }

    @Test("requireDouble coerces int to double")
    func requireDoubleFromInt() throws {
        let args: [String: Value] = ["amount": .int(42)]
        let result = try ToolHandlers.requireDouble(args, key: "amount")
        #expect(result == 42.0)
    }

    @Test("requireDouble throws on missing key")
    func requireDoubleMissing() {
        let args: [String: Value] = [:]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireDouble(args, key: "amount")
        }
    }

    @Test("requireDouble throws on string value")
    func requireDoubleWrongType() {
        let args: [String: Value] = ["amount": .string("fifty")]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireDouble(args, key: "amount")
        }
    }

    @Test("requireStringArray extracts string array")
    func requireStringArraySuccess() throws {
        let args: [String: Value] = ["ids": .array([.string("a"), .string("b"), .string("c")])]
        let result = try ToolHandlers.requireStringArray(args, key: "ids")
        #expect(result == ["a", "b", "c"])
    }

    @Test("requireStringArray throws on missing key")
    func requireStringArrayMissing() {
        let args: [String: Value] = [:]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireStringArray(args, key: "ids")
        }
    }

    @Test("requireStringArray throws on non-array value")
    func requireStringArrayWrongType() {
        let args: [String: Value] = ["ids": .string("not-an-array")]
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.requireStringArray(args, key: "ids")
        }
    }

    @Test("parseFlagColor maps valid colors")
    func parseFlagColorValid() {
        #expect(ToolHandlers.parseFlagColor("red") == .red)
        #expect(ToolHandlers.parseFlagColor("orange") == .orange)
        #expect(ToolHandlers.parseFlagColor("yellow") == .yellow)
        #expect(ToolHandlers.parseFlagColor("green") == .green)
        #expect(ToolHandlers.parseFlagColor("blue") == .blue)
        #expect(ToolHandlers.parseFlagColor("purple") == .purple)
        #expect(ToolHandlers.parseFlagColor("none") == FlagColor.none)
        #expect(ToolHandlers.parseFlagColor("RED") == .red)
    }

    @Test("parseFlagColor returns nil for nil or unknown")
    func parseFlagColorNil() {
        #expect(ToolHandlers.parseFlagColor(nil) == nil)
        #expect(ToolHandlers.parseFlagColor("invalid") == nil)
    }

    @Test("parseClearedStatus maps valid statuses")
    func parseClearedStatusValid() {
        #expect(ToolHandlers.parseClearedStatus("cleared") == .cleared)
        #expect(ToolHandlers.parseClearedStatus("uncleared") == .uncleared)
        #expect(ToolHandlers.parseClearedStatus("reconciled") == .reconciled)
        #expect(ToolHandlers.parseClearedStatus("CLEARED") == .cleared)
    }

    @Test("parseClearedStatus returns nil for nil or unknown")
    func parseClearedStatusNil() {
        #expect(ToolHandlers.parseClearedStatus(nil) == nil)
        #expect(ToolHandlers.parseClearedStatus("invalid") == nil)
    }

    @Test("parseDate parses YYYY-MM-DD format")
    func parseDateValid() {
        let date = ToolHandlers.parseDate("2025-06-15")
        #expect(date != nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        #expect(formatter.string(from: date!) == "2025-06-15")
    }

    @Test("parseDate returns nil for nil or invalid")
    func parseDateNil() {
        #expect(ToolHandlers.parseDate(nil) == nil)
        #expect(ToolHandlers.parseDate("not-a-date") == nil)
    }

    // MARK: - Call Routing (unknown tool)

    @Test("Unknown tool returns error result")
    func unknownToolReturnsError() async {
        let rateLimiter = RateLimiter(maxRequests: 200, windowSeconds: 3600)
        let client = YNABClient(accessToken: "fake-token", rateLimiter: rateLimiter)

        let result = await ToolHandlers.handleCall(
            name: "nonexistent_tool",
            arguments: nil,
            client: client
        )

        #expect(result.isError == true)
        if case .text(let text) = result.content.first {
            #expect(text.contains("Unknown tool"))
        } else {
            Issue.record("Expected text content in error result")
        }
    }
}
