import Foundation
import MCP
import SwiftYNAB

extension ToolHandlers {

    /// Creates new data; calling twice creates two records.
    static let createAnnotations = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
    )

    /// Sets fields to given values; repeating the same call has no further effect.
    static let updateAnnotations = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
    )

    static let writeSpecs: [ToolSpec] = [
        createTransaction,
        updateTransaction,
        bulkUpdateTransactions,
        renamePayee,
        setCategoryAssigned,
    ]

    // MARK: - Transactions

    static let createTransaction = ToolSpec(
        name: "create_transaction",
        title: "Create transaction",
        description: "Create a transaction. Amount is in currency units (negative for spending). New transactions are approved unless approved=false.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "account_id": Schema.string("Account ID (see list_accounts)"),
                "date": Schema.date("Transaction date"),
                "amount": Schema.amount,
                "payee_name": Schema.string("Payee name. YNAB matches an existing payee or creates one."),
                "category_id": Schema.string("Category ID (see list_categories)"),
                "memo": Schema.string("Memo"),
                "cleared": Schema.cleared,
                "approved": Schema.boolean("Approved status (default true)"),
                "flag_color": Schema.flagColor,
            ],
            required: ["account_id", "date", "amount"]
        ),
        annotations: createAnnotations
    ) { args, client in
        let transaction = NewTransaction(
            accountId: try requireString(args, key: "account_id"),
            date: try requireDateString(args, key: "date"),
            amount: Int64(Formatters.milliunits(from: try requireDouble(args, key: "amount"))),
            payeeId: nil,
            payeeName: args["payee_name"]?.stringValue,
            categoryId: args["category_id"]?.stringValue,
            memo: args["memo"]?.stringValue,
            cleared: try parseClearedStatus(args["cleared"]?.stringValue) ?? .uncleared,
            approved: try optionalBool(args, key: "approved") ?? true,
            flagColor: try parseFlagColor(args["flag_color"]?.stringValue),
            subtransactions: nil,
            importId: nil
        )
        let created = try await client.createTransaction(
            planId: planId(args, client: client),
            transaction: transaction
        )
        return textResult(Formatters.formatTransactionDetail(created, heading: "Transaction Created"))
    }

    static let updateTransaction = ToolSpec(
        name: "update_transaction",
        title: "Update transaction",
        description: "Update one transaction. Only the fields you pass are changed. Amount is in currency units (negative for spending).",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "transaction_id": Schema.string("Transaction ID"),
                "account_id": Schema.string("Move the transaction to this account"),
                "date": Schema.date("Transaction date"),
                "amount": Schema.amount,
                "payee_name": Schema.string("Payee name"),
                "category_id": Schema.string("Category ID (see list_categories)"),
                "memo": Schema.string("Memo"),
                "cleared": Schema.cleared,
                "approved": Schema.boolean("Approved status"),
                "flag_color": Schema.flagColor,
            ],
            required: ["transaction_id"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let transactionId = try requireString(args, key: "transaction_id")
        let date: String? = args["date"] == nil ? nil : try requireDateString(args, key: "date")
        let amount = try optionalDouble(args, key: "amount").map { Int64(Formatters.milliunits(from: $0)) }

        let transaction = ExistingTransaction(
            accountId: args["account_id"]?.stringValue,
            date: date,
            amount: amount,
            payeeId: nil,
            payeeName: args["payee_name"]?.stringValue,
            categoryId: args["category_id"]?.stringValue,
            memo: args["memo"]?.stringValue,
            cleared: try parseClearedStatus(args["cleared"]?.stringValue),
            approved: try optionalBool(args, key: "approved"),
            flagColor: try parseFlagColor(args["flag_color"]?.stringValue),
            subtransactions: nil
        )
        guard transaction.hasChanges else {
            throw YNABMCPError.invalidParameter("update_transaction", detail: "pass at least one field to change")
        }
        let updated = try await client.updateTransaction(
            planId: planId(args, client: client),
            transactionId: transactionId,
            transaction: transaction
        )
        return textResult(Formatters.formatTransactionDetail(updated, heading: "Transaction Updated"))
    }

    static let bulkUpdateTransactions = ToolSpec(
        name: "bulk_update_transactions",
        title: "Bulk update transactions",
        description: "Apply the same changes to many transactions in one request (one API call). Useful for approving or categorizing a batch.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "transaction_ids": Schema.stringArray("Transaction IDs to update"),
                "category_id": Schema.string("Category ID to set"),
                "payee_name": Schema.string("Payee name to set"),
                "approved": Schema.boolean("Approved status to set"),
                "flag_color": Schema.flagColor,
                "cleared": Schema.cleared,
                "memo": Schema.string("Memo to set"),
            ],
            required: ["transaction_ids"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let ids = try requireStringArray(args, key: "transaction_ids")
        let categoryId = args["category_id"]?.stringValue
        let payeeName = args["payee_name"]?.stringValue
        let approved = try optionalBool(args, key: "approved")
        let flagColor = try parseFlagColor(args["flag_color"]?.stringValue)
        let cleared = try parseClearedStatus(args["cleared"]?.stringValue)
        let memo = args["memo"]?.stringValue

        let hasUpdate = categoryId != nil || payeeName != nil || approved != nil
            || flagColor != nil || cleared != nil || memo != nil
        guard hasUpdate else {
            throw YNABMCPError.invalidParameter(
                "bulk_update_transactions",
                detail: "pass at least one of category_id, payee_name, approved, flag_color, cleared, memo"
            )
        }

        let transactions = ids.map { id in
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
        let updated = try await client.updateTransactions(
            planId: planId(args, client: client),
            transactions: transactions
        )
        var title = "# Bulk Update Complete\n\nUpdated \(updated.count) of \(ids.count) transactions.\n"
        let missing = Set(ids).subtracting(updated.map(\.id))
        if !missing.isEmpty {
            title += "Not updated: " + missing.sorted().map { "`\($0)`" }.joined(separator: ", ") + "\n"
        }
        return textResult(Formatters.formatTransactionDetailTable(updated, title: title))
    }

    // MARK: - Payees

    static let renamePayee = ToolSpec(
        name: "rename_payee",
        title: "Rename payee",
        description: "Rename a payee everywhere it is used. This does not merge duplicate payees; do that in the YNAB app.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "payee_id": Schema.string("Payee ID (see list_payees)"),
                "name": Schema.string("New payee name (max 500 characters)"),
            ],
            required: ["payee_id", "name"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let name = try requireString(args, key: "name")
        guard name.count <= 500 else {
            throw YNABMCPError.invalidParameter("name", detail: "must be 500 characters or fewer")
        }
        let payee = try await client.renamePayee(
            planId: planId(args, client: client),
            payeeId: try requireString(args, key: "payee_id"),
            name: name
        )
        return textResult("# Payee Renamed\n\n- **Name**: \(payee.name)\n- **ID**: `\(payee.id)`")
    }

    // MARK: - Categories

    static let setCategoryAssigned = ToolSpec(
        name: "set_category_assigned",
        title: "Set category assigned amount",
        description: "Set the amount assigned (budgeted) to a category for a month. This replaces the current assigned amount; it does not add to it.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "month": Schema.month,
                "category_id": Schema.string("Category ID (see list_categories)"),
                "amount": Schema.number("Total amount to assign for the month, in currency units (e.g. 500.00)"),
            ],
            required: ["month", "category_id", "amount"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let month = try requireMonth(args)
        let category = try await client.updateCategoryAssigned(
            planId: planId(args, client: client),
            month: month,
            categoryId: try requireString(args, key: "category_id"),
            budgeted: Formatters.milliunits(from: try requireDouble(args, key: "amount"))
        )
        let money = Formatters.money
        let lines = [
            "# Category Assigned Amount Updated\n",
            "- **Category**: \(category.name)",
            "- **Month**: \(month)",
            "- **Assigned**: \(money(category.budgeted, category.budgetedFormatted))",
            "- **Activity**: \(money(category.activity, category.activityFormatted))",
            "- **Available**: \(money(category.balance, category.balanceFormatted))",
        ]
        return textResult(lines.joined(separator: "\n"))
    }
}

extension ExistingTransaction {
    var hasChanges: Bool {
        accountId != nil || date != nil || amount != nil || payeeId != nil || payeeName != nil
            || categoryId != nil || memo != nil || cleared != nil || approved != nil
            || flagColor != nil || subtransactions != nil
    }
}
