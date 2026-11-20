import Foundation
import MCP
import SwiftYNAB

/// What reconciling an account will do, computed before any write.
public struct ReconcilePlan: Equatable, Sendable {
    public var clearedBalance: Int
    public var statementBalance: Int
    /// IDs of cleared (not yet reconciled) transactions that will be locked.
    public var transactionIds: [String]

    /// Amount of the balance adjustment needed so the cleared balance matches the statement.
    public var adjustment: Int { statementBalance - clearedBalance }

    public init(clearedBalance: Int, statementBalance: Int, transactions: [TransactionDetail]) {
        self.clearedBalance = clearedBalance
        self.statementBalance = statementBalance
        self.transactionIds = transactions
            .filter { !$0.deleted && $0.cleared == .cleared }
            .map(\.id)
    }
}

extension ToolHandlers {

    static let reconciliationPayee = "Reconciliation Balance Adjustment"

    static let accountTypes = ["checking", "savings", "cash", "creditCard", "otherAsset", "otherLiability"]

    static let createAccount = ToolSpec(
        name: "create_account",
        title: "Create account",
        description: "Create an unlinked account. checking, savings, cash, and creditCard are on budget; otherAsset and otherLiability are tracking accounts (vehicles, investments, loans). Balance is the starting balance (negative for debt).",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "name": Schema.string("Account name"),
                "type": Schema.string("Account type", oneOf: accountTypes),
                "balance": Schema.number("Starting balance in currency units (negative for credit cards and liabilities)"),
            ],
            required: ["name", "type", "balance"]
        ),
        annotations: createAnnotations
    ) { args, client in
        let rawType = try requireString(args, key: "type")
        guard let type = SaveAccountType(rawValue: rawType) else {
            throw YNABMCPError.invalidParameter("type", detail: "'\(rawType)' is not one of \(accountTypes.joined(separator: ", "))")
        }
        let account = try await client.createAccount(
            planId: planId(args, client: client),
            name: try requireString(args, key: "name"),
            type: type,
            balance: Formatters.milliunits(from: try requireDouble(args, key: "balance"))
        )
        let lines = [
            "# Account Created\n",
            "- **Name**: \(account.name)",
            "- **Type**: \(account.type.rawValue) (\(account.onBudget ? "on budget" : "tracking"))",
            "- **Balance**: \(Formatters.money(account.balance, formatted: account.balanceFormatted))",
            "- **ID**: `\(account.id)`",
        ]
        return textResult(lines.joined(separator: "\n"))
    }

    static let reconcileAccount = ToolSpec(
        name: "reconcile_account",
        title: "Reconcile account",
        description: "Reconcile an account against a statement balance, like YNAB's Reconcile button: if the cleared balance differs, add a cleared '\(reconciliationPayee)' for the difference, then mark every cleared transaction reconciled. Also the way to update a tracking account's value (e.g. an HSA or a vehicle). Run with dry_run=true first and confirm with the user. Uses up to 5 API requests.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "account_id": Schema.string("Account ID (see list_accounts)"),
                "statement_balance": Schema.number("The account's actual balance per the bank statement or current value, in currency units (negative for debt)"),
                "date": Schema.date("Date for the adjustment transaction (default today)"),
                "adjustment_category_id": Schema.string("Category for the adjustment. Defaults to Inflow: Ready to Assign on budget accounts and none on tracking accounts."),
                "dry_run": Schema.boolean("Only report what would change (default false)"),
            ],
            required: ["account_id", "statement_balance"]
        ),
        annotations: createAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        let accountId = try requireString(args, key: "account_id")
        let statement = Formatters.milliunits(from: try requireDouble(args, key: "statement_balance"))
        let date = args["date"] == nil
            ? isoDay(Date())
            : try requireDateString(args, key: "date")
        let dryRun = try optionalBool(args, key: "dry_run") ?? false

        let account = try await client.getAccount(planId: planId, accountId: accountId)
        let transactions = try await client.listTransactions(planId: planId, accountId: accountId, query: TransactionQuery())
        let plan = ReconcilePlan(clearedBalance: account.clearedBalance, statementBalance: statement, transactions: transactions)

        let money = { (value: Int) in Formatters.money(value) }
        var lines = [
            dryRun ? "# Reconcile Preview: \(account.name)\n" : "# Reconciled: \(account.name)\n",
            "- **Cleared balance in YNAB**: \(money(plan.clearedBalance))",
            "- **Statement balance**: \(money(plan.statementBalance))",
            "- **Adjustment**: \(plan.adjustment == 0 ? "none needed" : money(plan.adjustment))",
            "- **Cleared transactions to lock**: \(plan.transactionIds.count)",
        ]
        if account.unclearedBalance != 0 {
            lines.append("- **Uncleared (left alone)**: \(money(account.unclearedBalance))")
        }
        if dryRun {
            lines.append("\nDry run: nothing was changed.")
            return textResult(lines.joined(separator: "\n"))
        }

        if plan.adjustment != 0 {
            var categoryId = args["adjustment_category_id"]?.stringValue
            if categoryId == nil && account.onBudget {
                categoryId = try await readyToAssignCategoryId(planId: planId, client: client)
            }
            let adjustment = NewTransaction(
                accountId: accountId,
                date: date,
                amount: Int64(plan.adjustment),
                payeeId: nil,
                payeeName: reconciliationPayee,
                categoryId: categoryId,
                memo: "Entered automatically by reconcile_account",
                cleared: .reconciled,
                approved: true,
                flagColor: nil,
                subtransactions: nil,
                importId: nil
            )
            let created = try await client.createTransaction(planId: planId, transaction: adjustment)
            lines.append("- **Adjustment transaction**: `\(created.id)`")
        }
        if !plan.transactionIds.isEmpty {
            let updates = plan.transactionIds.map { id in
                SaveTransactionWithIdOrImportId(
                    id: id, importId: nil, accountId: nil, date: nil, amount: nil,
                    payeeId: nil, payeeName: nil, categoryId: nil, memo: nil,
                    cleared: .reconciled, approved: nil, flagColor: nil, subtransactions: nil
                )
            }
            let updated = try await client.updateTransactions(planId: planId, transactions: updates)
            lines.append("- **Locked**: \(updated.count) of \(plan.transactionIds.count) transactions")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    /// The internal "Inflow: Ready to Assign" category, where YNAB books income and adjustments.
    static func readyToAssignCategoryId(planId: String, client: YNABClient) async throws -> String {
        let groups = try await client.listCategories(planId: planId)
        let category = groups
            .filter { $0.internal && !$0.deleted }
            .flatMap(\.categories)
            .first { $0.name.lowercased().hasPrefix("inflow") && !$0.deleted }
        guard let category else {
            throw YNABMCPError.unexpectedResponse("could not find the Inflow: Ready to Assign category; pass adjustment_category_id")
        }
        return category.id
    }
}
