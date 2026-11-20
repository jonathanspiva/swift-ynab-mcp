import Foundation
import MCP
import SwiftYNAB

/// Requested edits to a scheduled transaction. nil means "keep the current value".
public struct ScheduledChanges: Equatable, Sendable {
    public var accountId: String?
    public var date: String?
    public var amount: Int?
    public var frequency: ScheduledTransactionFrequency?
    public var payeeId: String?
    public var payeeName: String?
    public var categoryId: String?
    public var memo: String?
    public var flagColor: FlagColor?

    public var isEmpty: Bool { self == ScheduledChanges() }

    public init(
        accountId: String? = nil,
        date: String? = nil,
        amount: Int? = nil,
        frequency: ScheduledTransactionFrequency? = nil,
        payeeId: String? = nil,
        payeeName: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        flagColor: FlagColor? = nil
    ) {
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.frequency = frequency
        self.payeeId = payeeId
        self.payeeName = payeeName
        self.categoryId = categoryId
        self.memo = memo
        self.flagColor = flagColor
    }

    /// YNAB's update replaces the whole scheduled transaction, so start from the current values.
    /// A new payee (name or transfer) replaces the old payee entirely.
    public func applied(to current: ScheduledTransactionDetail) -> SaveScheduledTransaction {
        let newPayee = payeeId != nil || payeeName != nil
        return SaveScheduledTransaction(
            accountId: accountId ?? current.accountId,
            date: date ?? current.dateNext,
            amount: amount ?? current.amount,
            payeeId: newPayee ? payeeId : current.payeeId,
            payeeName: newPayee ? payeeName : nil,
            categoryId: categoryId ?? current.categoryId,
            memo: memo ?? current.memo,
            flagColor: flagColor ?? current.flagColor,
            frequency: frequency ?? current.frequency
        )
    }
}

extension ToolHandlers {

    static let scheduledSpecs: [ToolSpec] = [
        createScheduledTransaction,
        updateScheduledTransaction,
        deleteScheduledTransaction,
    ]

    static let frequencies: [String] = [
        "never", "daily", "weekly", "everyOtherWeek", "twiceAMonth", "every4Weeks", "monthly",
        "everyOtherMonth", "every3Months", "every4Months", "twiceAYear", "yearly", "everyOtherYear",
    ]

    static let frequencySchema = Schema.string("How often it repeats ('never' for a one-time future transaction)", oneOf: frequencies)

    public static func parseFrequency(_ string: String?) throws -> ScheduledTransactionFrequency? {
        guard let string else { return nil }
        guard let frequency = ScheduledTransactionFrequency(rawValue: string) else {
            throw YNABMCPError.invalidParameter("frequency", detail: "'\(string)' is not one of \(frequencies.joined(separator: ", "))")
        }
        return frequency
    }

    /// Parse the editable fields shared by create and update. Transfer accounts are resolved by the caller.
    static func parseScheduledChanges(_ args: [String: Value]) throws -> (ScheduledChanges, transferAccountId: String?) {
        let changes = ScheduledChanges(
            accountId: args["account_id"]?.stringValue,
            date: args["date"] == nil ? nil : try requireDateString(args, key: "date"),
            amount: try optionalDouble(args, key: "amount").map(Formatters.milliunits),
            frequency: try parseFrequency(args["frequency"]?.stringValue),
            payeeName: args["payee_name"]?.stringValue,
            categoryId: args["category_id"]?.stringValue,
            memo: args["memo"]?.stringValue,
            flagColor: try parseFlagColor(args["flag_color"]?.stringValue)
        )
        return (changes, try optionalTransferAccount(args))
    }

    static func scheduledProperties(forUpdate: Bool) -> [String: Value] {
        var properties: [String: Value] = [
            "plan_id": Schema.planId,
            "account_id": Schema.string(forUpdate ? "Move to this account" : "Account ID (see list_accounts)"),
            "date": Schema.date(forUpdate ? "Next date it occurs (today or later, within 5 years)" : "First date it occurs (today or later, within 5 years)"),
            "amount": Schema.amount,
            "frequency": frequencySchema,
            "payee_name": Schema.string("Payee name"),
            "transfer_account_id": Schema.transferAccountId,
            "category_id": Schema.string("Category ID (see list_categories)"),
            "memo": Schema.string("Memo"),
            "flag_color": Schema.flagColor,
        ]
        if forUpdate {
            properties["scheduled_transaction_id"] = Schema.string("Scheduled transaction ID (see list_scheduled_transactions)")
        }
        return properties
    }

    static let createScheduledTransaction = ToolSpec(
        name: "create_scheduled_transaction",
        title: "Create scheduled transaction",
        description: "Schedule a future or recurring transaction (a bill, paycheck, or transfer). Amount is negative for spending. Pass transfer_account_id for a recurring transfer. The date must be today or later and within 5 years.",
        inputSchema: Schema.object(
            scheduledProperties(forUpdate: false),
            required: ["account_id", "date", "amount", "frequency"]
        ),
        annotations: createAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        var (changes, transferAccountId) = try parseScheduledChanges(args)
        guard let accountId = changes.accountId, let date = changes.date, changes.amount != nil, changes.frequency != nil else {
            throw YNABMCPError.missingParameter(["account_id", "date", "amount", "frequency"].first { args[$0] == nil } ?? "account_id")
        }
        if let transferAccountId {
            changes.payeeId = try await transferPayeeIds(for: [transferAccountId], planId: planId, client: client)[transferAccountId]
        }
        let created = try await client.createScheduledTransaction(
            planId: planId,
            transaction: SaveScheduledTransaction(
                accountId: accountId,
                date: date,
                amount: changes.amount,
                payeeId: changes.payeeId,
                payeeName: changes.payeeName,
                categoryId: changes.categoryId,
                memo: changes.memo,
                flagColor: changes.flagColor,
                frequency: changes.frequency
            )
        )
        return textResult(Formatters.formatScheduledDetail(created, heading: "Scheduled Transaction Created"))
    }

    static let updateScheduledTransaction = ToolSpec(
        name: "update_scheduled_transaction",
        title: "Update scheduled transaction",
        description: "Change a scheduled transaction. Only the fields you pass change; the rest are kept (this reads the current version first, so it costs 2 requests, 3 with a transfer). Scheduled splits can't be edited through the API.",
        inputSchema: Schema.object(
            scheduledProperties(forUpdate: true),
            required: ["scheduled_transaction_id"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        let id = try requireString(args, key: "scheduled_transaction_id")
        var (changes, transferAccountId) = try parseScheduledChanges(args)
        guard !changes.isEmpty || transferAccountId != nil else {
            throw YNABMCPError.invalidParameter("update_scheduled_transaction", detail: "pass at least one field to change")
        }

        let current = try await client.getScheduledTransaction(planId: planId, id: id)
        guard current.subtransactions.allSatisfy(\.deleted) else {
            throw YNABMCPError.invalidParameter(
                "scheduled_transaction_id",
                detail: "this is a scheduled split; the API would drop its lines. Edit it in the YNAB app, or delete and recreate it."
            )
        }
        if let transferAccountId {
            changes.payeeId = try await transferPayeeIds(for: [transferAccountId], planId: planId, client: client)[transferAccountId]
        }
        let updated = try await client.updateScheduledTransaction(
            planId: planId,
            id: id,
            transaction: changes.applied(to: current)
        )
        return textResult(Formatters.formatScheduledDetail(updated, heading: "Scheduled Transaction Updated"))
    }

    static let deleteScheduledTransaction = ToolSpec(
        name: "delete_scheduled_transaction",
        title: "Delete scheduled transaction",
        description: "Delete a scheduled transaction so it stops recurring. Transactions it already entered are not affected. Confirm with the user first.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "scheduled_transaction_id": Schema.string("Scheduled transaction ID (see list_scheduled_transactions)"),
            ],
            required: ["scheduled_transaction_id"]
        ),
        annotations: deleteAnnotations
    ) { args, client in
        let deleted = try await client.deleteScheduledTransaction(
            planId: planId(args, client: client),
            id: try requireString(args, key: "scheduled_transaction_id")
        )
        return textResult(Formatters.formatScheduledDetail(deleted, heading: "Scheduled Transaction Deleted"))
    }
}

extension Formatters {
    public static func formatScheduledDetail(_ txn: ScheduledTransactionDetail, heading: String) -> String {
        var lines = ["# \(heading)\n"]
        lines.append("- **ID**: `\(txn.id)`")
        lines.append("- **Amount**: \(money(txn.amount, formatted: txn.amountFormatted))")
        lines.append("- **Frequency**: \(txn.frequency.rawValue)")
        lines.append("- **Next date**: \(txn.dateNext)")
        lines.append("- **Account**: \(txn.accountName)")
        if let payee = txn.payeeName {
            lines.append("- **Payee**: \(payee)")
        }
        if let category = txn.categoryName {
            lines.append("- **Category**: \(category)")
        }
        if let memo = txn.memo, !memo.isEmpty {
            lines.append("- **Memo**: \(memo)")
        }
        if let flagColor = txn.flagColor, flagColor != .none {
            lines.append("- **Flag**: \(flagColor.rawValue)")
        }
        let parts = txn.subtransactions.filter { !$0.deleted }
        if !parts.isEmpty {
            lines.append("\n## Split\n")
            for sub in parts {
                lines.append("- \(money(sub.amount, formatted: sub.amountFormatted)): \(sub.categoryName ?? "-")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
