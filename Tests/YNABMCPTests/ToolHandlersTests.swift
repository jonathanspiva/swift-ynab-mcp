import Foundation
import Testing
import MCP
import SwiftYNAB
@testable import YNABMCPLib

@Suite("ToolHandlers")
struct ToolHandlersTests {

    static let readToolNames: Set<String> = [
        "list_plans",
        "list_accounts",
        "list_categories",
        "get_plan_summary",
        "get_month_summary",
        "list_transactions",
        "get_transaction",
        "get_transactions_by_payee",
        "get_transactions_by_category",
        "list_payees",
        "list_scheduled_transactions",
    ]

    static let writeToolNames: Set<String> = [
        "create_transaction",
        "update_transaction",
        "bulk_update_transactions",
        "rename_payee",
        "set_category_assigned",
    ]

    func makeClient() -> YNABClient {
        YNABClient(accessToken: "fake-token", rateLimiter: RateLimiter(maxRequests: 200, windowSeconds: 3600))
    }

    func text(of result: CallTool.Result) -> String {
        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return text
    }

    // MARK: - Registry

    @Test("Tool names match expected set")
    func toolNameSet() {
        let names = Set(ToolHandlers.allTools.map(\.name))
        #expect(names == Self.readToolNames.union(Self.writeToolNames))
        #expect(ToolHandlers.allTools.count == names.count, "Tool names must be unique")
    }

    @Test("Tool names are snake_case")
    func toolNamesSnakeCase() {
        for tool in ToolHandlers.allTools {
            #expect(tool.name.allSatisfy { $0.isLowercase || $0 == "_" }, "'\(tool.name)' should be snake_case")
        }
    }

    @Test("Every tool has a title and description")
    func toolsHaveTitlesAndDescriptions() {
        for tool in ToolHandlers.allTools {
            #expect(!(tool.description ?? "").isEmpty, "'\(tool.name)' needs a description")
            #expect(!(tool.title ?? "").isEmpty, "'\(tool.name)' needs a title")
            #expect(tool.annotations.title == tool.title, "'\(tool.name)' annotation title should match")
        }
    }

    @Test("Read tools are annotated read-only and idempotent")
    func readToolAnnotations() {
        for spec in ToolHandlers.allSpecs where Self.readToolNames.contains(spec.tool.name) {
            #expect(!spec.isWrite)
            #expect(spec.tool.annotations.readOnlyHint == true)
            #expect(spec.tool.annotations.idempotentHint == true)
        }
    }

    @Test("Write tools are annotated as writes and not destructive")
    func writeToolAnnotations() {
        for spec in ToolHandlers.allSpecs where Self.writeToolNames.contains(spec.tool.name) {
            #expect(spec.isWrite)
            #expect(spec.tool.annotations.readOnlyHint == false)
            #expect(spec.tool.annotations.destructiveHint == false)
        }
        #expect(ToolHandlers.createTransaction.tool.annotations.idempotentHint == false)
        #expect(ToolHandlers.updateTransaction.tool.annotations.idempotentHint == true)
    }

    @Test("Schemas are closed objects whose required keys exist as properties")
    func schemasAreWellFormed() {
        for tool in ToolHandlers.allTools {
            guard let schema = tool.inputSchema.objectValue else {
                Issue.record("'\(tool.name)' inputSchema should be an object")
                continue
            }
            #expect(schema["type"]?.stringValue == "object")
            #expect(schema["additionalProperties"]?.boolValue == false)
            let properties = schema["properties"]?.objectValue ?? [:]
            for key in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                #expect(properties[key] != nil, "'\(tool.name)' requires undeclared '\(key)'")
            }
        }
    }

    @Test("plan_id is optional on every tool")
    func planIdOptional() {
        for tool in ToolHandlers.allTools where tool.name != "list_plans" {
            let schema = tool.inputSchema.objectValue
            #expect(schema?["properties"]?.objectValue?["plan_id"] != nil, "'\(tool.name)' should accept plan_id")
            let required = schema?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            #expect(!required.contains("plan_id"), "'\(tool.name)' should not require plan_id")
        }
    }

    // MARK: - Read-only mode

    @Test("Read-only mode hides write tools")
    func readOnlyHidesWrites() {
        let names = Set(ToolHandlers.tools(readOnly: true).map(\.name))
        #expect(names == Self.readToolNames)
        #expect(ToolHandlers.tools(readOnly: false).count == ToolHandlers.allTools.count)
    }

    @Test("Read-only mode rejects write calls without touching YNAB")
    func readOnlyRejectsWrites() async {
        let result = await ToolHandlers.handleCall(
            name: "create_transaction",
            arguments: ["account_id": "a", "date": "2026-01-01", "amount": .double(-1)],
            client: makeClient(),
            readOnly: true
        )
        #expect(result.isError == true)
        #expect(text(of: result).contains("YNAB_READ_ONLY"))
    }

    // MARK: - Call routing and validation (no network: all fail before the API call)

    @Test("Unknown tool returns error result")
    func unknownToolReturnsError() async {
        let result = await ToolHandlers.handleCall(name: "nonexistent_tool", arguments: nil, client: makeClient())
        #expect(result.isError == true)
        #expect(text(of: result).contains("Unknown tool"))
    }

    @Test("Invalid flag color is rejected, not silently dropped")
    func invalidFlagColorRejected() async {
        let result = await ToolHandlers.handleCall(
            name: "update_transaction",
            arguments: ["transaction_id": "t1", "flag_color": "magenta"],
            client: makeClient()
        )
        #expect(result.isError == true)
        #expect(text(of: result).contains("flag_color"))
    }

    @Test("update_transaction with no fields is rejected")
    func updateWithoutFieldsRejected() async {
        let result = await ToolHandlers.handleCall(
            name: "update_transaction",
            arguments: ["transaction_id": "t1"],
            client: makeClient()
        )
        #expect(result.isError == true)
        #expect(text(of: result).contains("at least one field"))
    }

    @Test("bulk_update_transactions with no fields is rejected")
    func bulkWithoutFieldsRejected() async {
        let result = await ToolHandlers.handleCall(
            name: "bulk_update_transactions",
            arguments: ["transaction_ids": .array(["a", "b"])],
            client: makeClient()
        )
        #expect(result.isError == true)
    }

    @Test("Malformed dates are rejected")
    func malformedDateRejected() async {
        let result = await ToolHandlers.handleCall(
            name: "list_transactions",
            arguments: ["since_date": "01/02/2026"],
            client: makeClient()
        )
        #expect(result.isError == true)
        #expect(text(of: result).contains("since_date"))
    }

    @Test("Out-of-range limit is rejected")
    func badLimitRejected() async {
        let result = await ToolHandlers.handleCall(
            name: "list_transactions",
            arguments: ["limit": .int(0)],
            client: makeClient()
        )
        #expect(result.isError == true)
        #expect(text(of: result).contains("limit"))
    }

    // MARK: - Parameter helpers

    @Test("planId falls back to the client default")
    func planIdDefault() {
        let client = YNABClient(accessToken: "x", rateLimiter: RateLimiter(), defaultPlanId: "plan-123")
        #expect(ToolHandlers.planId([:], client: client) == "plan-123")
        #expect(ToolHandlers.planId(["plan_id": ""], client: client) == "plan-123")
        #expect(ToolHandlers.planId(["plan_id": "other"], client: client) == "other")
        #expect(makeClient().defaultPlanId == "last-used")
    }

    @Test("requireString extracts, and throws on missing, empty, or wrong type")
    func requireString() throws {
        #expect(try ToolHandlers.requireString(["k": "v"], key: "k") == "v")
        #expect(throws: YNABMCPError.missingParameter("k")) { try ToolHandlers.requireString([:], key: "k") }
        #expect(throws: YNABMCPError.missingParameter("k")) { try ToolHandlers.requireString(["k": ""], key: "k") }
        #expect(throws: YNABMCPError.missingParameter("k")) { try ToolHandlers.requireString(["k": .int(1)], key: "k") }
    }

    @Test("requireDouble accepts ints and doubles, rejects strings")
    func requireDouble() throws {
        #expect(try ToolHandlers.requireDouble(["a": .double(-50.25)], key: "a") == -50.25)
        #expect(try ToolHandlers.requireDouble(["a": .int(42)], key: "a") == 42.0)
        #expect(throws: YNABMCPError.missingParameter("a")) { try ToolHandlers.requireDouble([:], key: "a") }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireDouble(["a": "fifty"], key: "a") }
    }

    @Test("optionalBool rejects non-booleans")
    func optionalBool() throws {
        #expect(try ToolHandlers.optionalBool([:], key: "b") == nil)
        #expect(try ToolHandlers.optionalBool(["b": true], key: "b") == true)
        #expect(throws: YNABMCPError.self) { try ToolHandlers.optionalBool(["b": "yes"], key: "b") }
    }

    @Test("requireStringArray requires a non-empty array of only strings")
    func requireStringArray() throws {
        #expect(try ToolHandlers.requireStringArray(["ids": .array(["a", "b"])], key: "ids") == ["a", "b"])
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireStringArray([:], key: "ids") }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireStringArray(["ids": "a"], key: "ids") }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireStringArray(["ids": .array([])], key: "ids") }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireStringArray(["ids": .array(["a", .int(1)])], key: "ids") }
    }

    @Test("parseFlagColor maps colors case-insensitively and throws on unknown")
    func parseFlagColor() throws {
        #expect(try ToolHandlers.parseFlagColor(nil) == nil)
        #expect(try ToolHandlers.parseFlagColor("RED") == .red)
        #expect(try ToolHandlers.parseFlagColor("purple") == .purple)
        #expect(try ToolHandlers.parseFlagColor("none") == FlagColor.none)
        #expect(throws: YNABMCPError.self) { try ToolHandlers.parseFlagColor("magenta") }
    }

    @Test("parseClearedStatus maps statuses and throws on unknown")
    func parseClearedStatus() throws {
        #expect(try ToolHandlers.parseClearedStatus(nil) == nil)
        #expect(try ToolHandlers.parseClearedStatus("CLEARED") == .cleared)
        #expect(try ToolHandlers.parseClearedStatus("reconciled") == .reconciled)
        #expect(throws: YNABMCPError.self) { try ToolHandlers.parseClearedStatus("pending") }
    }

    @Test("parseDate accepts only strict YYYY-MM-DD")
    func parseDate() {
        #expect(ToolHandlers.parseDate("2025-06-15").map(Formatters.isoDay) == "2025-06-15")
        #expect(ToolHandlers.parseDate(nil) == nil)
        #expect(ToolHandlers.parseDate("not-a-date") == nil)
        #expect(ToolHandlers.parseDate("2025-6-15") == nil)
        #expect(ToolHandlers.parseDate("2025-02-30") == nil)
    }

    @Test("requireMonth accepts 'current' and first-of-month dates only")
    func requireMonth() throws {
        #expect(try ToolHandlers.requireMonth(["month": "current"]) == "current")
        #expect(try ToolHandlers.requireMonth(["month": "Current"]) == "current")
        #expect(try ToolHandlers.requireMonth(["month": "2026-03-01"]) == "2026-03-01")
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireMonth(["month": "2026-03-15"]) }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.requireMonth(["month": "March"]) }
    }

    @Test("boundedLimit defaults, accepts in-range, rejects out-of-range")
    func boundedLimit() throws {
        #expect(try ToolHandlers.boundedLimit([:], default: 300, max: 1000) == 300)
        #expect(try ToolHandlers.boundedLimit(["limit": .int(50)], default: 300, max: 1000) == 50)
        #expect(throws: YNABMCPError.self) { try ToolHandlers.boundedLimit(["limit": .int(1001)], default: 300, max: 1000) }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.boundedLimit(["limit": "10"], default: 300, max: 1000) }
    }

    @Test("Every list tool that can return unbounded rows exposes a limit")
    func listToolsHaveLimits() {
        for name in ["list_transactions", "get_transactions_by_payee", "get_transactions_by_category", "list_payees"] {
            let tool = ToolHandlers.allTools.first { $0.name == name }
            #expect(tool?.inputSchema.objectValue?["properties"]?.objectValue?["limit"] != nil, "'\(name)' needs limit")
        }
    }

    @Test("applyLimit truncates and explains")
    func applyLimit() {
        let (rows, note) = ToolHandlers.applyLimit(Array(1...5), limit: 3)
        #expect(rows == [1, 2, 3])
        #expect(note.contains("3 of 5"))
        let (all, none) = ToolHandlers.applyLimit(Array(1...2), limit: 3)
        #expect(all == [1, 2])
        #expect(none.isEmpty)
    }
}

extension Formatters {
    static func isoDay(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
