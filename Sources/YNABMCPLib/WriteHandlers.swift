import Foundation
import MCP
import SwiftYNAB

// MARK: - Write Handler Implementations

extension ToolHandlers {

    static func handleCreateTransaction(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let accountId = try requireString(args, key: "account_id")
        let date = try requireString(args, key: "date")
        let amountDollars = try requireDouble(args, key: "amount")

        let payeeName = args["payee_name"]?.stringValue
        let categoryId = args["category_id"]?.stringValue
        let memo = args["memo"]?.stringValue
        let cleared = parseClearedStatus(args["cleared"]?.stringValue)

        let milliunits = Formatters.milliunits(from: amountDollars)

        let txn = try await client.createTransaction(
            budgetId: budgetId,
            accountId: accountId,
            date: date,
            amount: milliunits,
            payeeName: payeeName,
            categoryId: categoryId,
            memo: memo,
            cleared: cleared
        )

        return CallTool.Result(content: [.text(Formatters.formatTransactionDetail(txn))])
    }

    static func handleUpdateTransaction(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let transactionId = try requireString(args, key: "transaction_id")

        let accountId = args["account_id"]?.stringValue
        let date = args["date"]?.stringValue
        let payeeName = args["payee_name"]?.stringValue
        let categoryId = args["category_id"]?.stringValue
        let memo = args["memo"]?.stringValue
        let cleared = parseClearedStatus(args["cleared"]?.stringValue)
        let approved = args["approved"]?.boolValue
        let flagColor = parseFlagColor(args["flag_color"]?.stringValue)

        let milliunits: Int?
        if let amountDollars = args["amount"]?.doubleValue ?? args["amount"]?.intValue.map({ Double($0) }) {
            milliunits = Formatters.milliunits(from: amountDollars)
        } else {
            milliunits = nil
        }

        let txn = try await client.updateTransaction(
            budgetId: budgetId,
            transactionId: transactionId,
            accountId: accountId,
            date: date,
            amount: milliunits,
            payeeName: payeeName,
            categoryId: categoryId,
            memo: memo,
            cleared: cleared,
            approved: approved,
            flagColor: flagColor
        )

        return CallTool.Result(content: [.text(Formatters.formatTransactionDetail(txn))])
    }

    static func handleBulkUpdateTransactions(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let transactionIds = try requireStringArray(args, key: "transaction_ids")

        let categoryId = args["category_id"]?.stringValue
        let payeeName = args["payee_name"]?.stringValue
        let approved = args["approved"]?.boolValue
        let flagColor = parseFlagColor(args["flag_color"]?.stringValue)
        let cleared = parseClearedStatus(args["cleared"]?.stringValue)
        let memo = args["memo"]?.stringValue

        let hasUpdate = categoryId != nil || payeeName != nil || approved != nil
            || flagColor != nil || cleared != nil || memo != nil
        guard hasUpdate else {
            throw YNABMCPError.invalidParameter(
                "bulk_update_transactions",
                detail: "At least one update field (category_id, payee_name, approved, flag_color, cleared, memo) must be provided"
            )
        }

        let transactions = transactionIds.map { id in
            SaveTransactionWithIdOrImportId(
                id: id,
                importId: nil,
                accountId: nil,
                date: nil,
                amount: nil,
                payeeId: nil,
                payeeName: payeeName,
                categoryId: categoryId,
                memo: memo,
                cleared: cleared,
                approved: approved,
                flagColor: flagColor,
                subtransactions: nil
            )
        }

        let updated = try await client.bulkUpdateTransactions(
            budgetId: budgetId,
            transactions: transactions
        )

        let title = "# Bulk Update Complete\n\nUpdated \(updated.count) transactions.\n"
        return CallTool.Result(content: [.text(Formatters.formatTransactionDetailTable(updated, title: title))])
    }

    static func handleRenamePayee(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let payeeId = try requireString(args, key: "payee_id")
        let name = try requireString(args, key: "name")

        let payee = try await client.renamePayee(
            budgetId: budgetId,
            payeeId: payeeId,
            name: name
        )

        var lines: [String] = ["# Payee Renamed\n"]
        lines.append("- **Name**: \(payee.name)")
        lines.append("- **ID**: `\(payee.id)`")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleUpdateCategoryBudget(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let month = try requireString(args, key: "month")
        let categoryId = try requireString(args, key: "category_id")
        let amountDollars = try requireDouble(args, key: "amount")

        let milliunits = Formatters.milliunits(from: amountDollars)

        let category = try await client.updateCategoryBudget(
            budgetId: budgetId,
            month: month,
            categoryId: categoryId,
            budgeted: milliunits
        )

        var lines: [String] = ["# Category Budget Updated\n"]
        lines.append("- **Category**: \(category.name)")
        lines.append("- **Month**: \(month)")
        lines.append("- **Budgeted**: \(Formatters.dollars(from: category.budgeted))")
        lines.append("- **Activity**: \(Formatters.dollars(from: category.activity))")
        lines.append("- **Available**: \(Formatters.dollars(from: category.balance))")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
