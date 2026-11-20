import Foundation
import MCP
import SwiftYNAB

extension ToolHandlers {

    static let readOnlyAnnotations = Tool.Annotations(
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
    )

    /// Default and maximum rows returned by transaction list tools, to keep results inside
    /// MCP client output limits. Narrow the date range to see more.
    static let defaultTransactionLimit = 200
    static let maxTransactionLimit = 1000
    static let defaultPayeeLimit = 300
    static let maxPayeeLimit = 1000

    static let readSpecs: [ToolSpec] = [
        listPlans,
        listAccounts,
        listCategories,
        getPlanSummary,
        getMonthSummary,
        listTransactions,
        getTransaction,
        getTransactionsByPayee,
        getTransactionsByCategory,
        listPayees,
        listScheduledTransactions,
    ]

    // MARK: - Plans

    static let listPlans = ToolSpec(
        name: "list_plans",
        title: "List plans",
        description: "List all YNAB plans (budgets) with names, IDs, and currency. Most tools default to the last-used plan, so this is only needed when working with more than one.",
        inputSchema: Schema.object([:]),
        annotations: readOnlyAnnotations
    ) { _, client in
        let plans = try await client.listPlans()
        var lines: [String] = ["# YNAB Plans\n"]
        for plan in plans {
            let currency = plan.currencyFormat?.isoCode ?? "unknown currency"
            lines.append("- **\(plan.name)** (\(currency))")
            lines.append("  ID: `\(plan.id)`")
            if let lastModified = plan.lastModifiedOn {
                lines.append("  Last modified: \(lastModified)")
            }
        }
        lines.append("\nDefault plan for tool calls: `\(client.defaultPlanId)`")
        return textResult(lines.joined(separator: "\n"))
    }

    static let getPlanSummary = ToolSpec(
        name: "get_plan_summary",
        title: "Plan summary",
        description: "Overview of a plan: open account balances plus every visible category with assigned, activity, and available amounts for the current month.",
        inputSchema: Schema.object(["plan_id": Schema.planId]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        async let accountsTask = client.listAccounts(planId: planId)
        async let groupsTask = client.listCategories(planId: planId)
        let (accounts, groups) = try await (accountsTask, groupsTask)

        var lines: [String] = ["# Plan Summary\n", "## Accounts\n"]
        for account in accounts where !account.deleted && !account.closed {
            let budget = account.onBudget ? "" : " (tracking)"
            lines.append("- **\(account.name)**\(budget): \(Formatters.money(account.balance, formatted: account.balanceFormatted))")
        }
        lines.append("\n## Categories (current month)\n")
        appendCategoryGroups(groups, to: &lines)
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Accounts

    static let listAccounts = ToolSpec(
        name: "list_accounts",
        title: "List accounts",
        description: "List accounts in a plan with IDs, type, balances, and on-budget status. Closed accounts are hidden unless include_closed is true.",
        inputSchema: Schema.object([
            "plan_id": Schema.planId,
            "include_closed": Schema.boolean("Include closed accounts (default false)"),
        ]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let includeClosed = try optionalBool(args, key: "include_closed") ?? false
        let accounts = try await client.listAccounts(planId: planId(args, client: client))

        var lines: [String] = ["# Accounts\n"]
        for account in accounts where !account.deleted && (includeClosed || !account.closed) {
            let status = account.closed ? " (CLOSED)" : ""
            let balance = Formatters.money(account.balance, formatted: account.balanceFormatted)
            lines.append("- **\(account.name)**\(status): \(balance)")
            lines.append("  Type: \(account.type.rawValue) | On budget: \(account.onBudget ? "Yes" : "No")")
            let cleared = Formatters.money(account.clearedBalance, formatted: account.clearedBalanceFormatted)
            let uncleared = Formatters.money(account.unclearedBalance, formatted: account.unclearedBalanceFormatted)
            lines.append("  Cleared: \(cleared) | Uncleared: \(uncleared)")
            if let reconciled = account.lastReconciledAt {
                lines.append("  Last reconciled: \(reconciled)")
            }
            if account.directImportInError == true {
                lines.append("  Warning: bank import connection is in an error state")
            }
            lines.append("  ID: `\(account.id)`")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Categories

    static let listCategories = ToolSpec(
        name: "list_categories",
        title: "List categories",
        description: "List category groups and categories with IDs and current-month amounts. Use these IDs when creating or updating transactions.",
        inputSchema: Schema.object([
            "plan_id": Schema.planId,
            "include_hidden": Schema.boolean("Include hidden categories (default false)"),
        ]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let includeHidden = try optionalBool(args, key: "include_hidden") ?? false
        let groups = try await client.listCategories(planId: planId(args, client: client))

        var lines: [String] = ["# Categories\n"]
        appendCategoryGroups(groups, to: &lines, includeHidden: includeHidden, includeIds: true)
        return textResult(lines.joined(separator: "\n"))
    }

    static func appendCategoryGroups(
        _ groups: [CategoryGroupWithCategories],
        to lines: inout [String],
        includeHidden: Bool = false,
        includeIds: Bool = false
    ) {
        for group in groups where !group.deleted && !group.internal && (includeHidden || !group.hidden) {
            lines.append("### \(group.name)")
            for cat in group.categories where !cat.deleted && (includeHidden || !cat.hidden) {
                let assigned = Formatters.money(cat.budgeted, formatted: cat.budgetedFormatted)
                let activity = Formatters.money(cat.activity, formatted: cat.activityFormatted)
                let available = Formatters.money(cat.balance, formatted: cat.balanceFormatted)
                let id = includeIds ? " `\(cat.id)`" : ""
                let hidden = cat.hidden ? " (hidden)" : ""
                lines.append("- **\(cat.name)**\(hidden)\(id): Assigned \(assigned) | Activity \(activity) | Available \(available)")
            }
            lines.append("")
        }
    }

    // MARK: - Months

    static let getMonthSummary = ToolSpec(
        name: "get_month_summary",
        title: "Month summary",
        description: "Income, assigned, activity, Ready to Assign, age of money, and a per-category breakdown for one month.",
        inputSchema: Schema.object(
            ["plan_id": Schema.planId, "month": Schema.month],
            required: ["month"]
        ),
        annotations: readOnlyAnnotations
    ) { args, client in
        let month = try requireMonth(args)
        let detail = try await client.getMonth(planId: planId(args, client: client), month: month)
        let esc = Formatters.escapeTableCell
        let money = Formatters.money

        var lines: [String] = ["# Month: \(detail.month)\n"]
        lines.append("- Income: \(money(detail.income, detail.incomeFormatted))")
        lines.append("- Assigned: \(money(detail.budgeted, detail.budgetedFormatted))")
        lines.append("- Activity: \(money(detail.activity, detail.activityFormatted))")
        lines.append("- Ready to Assign: \(money(detail.toBeBudgeted, detail.toBeBudgetedFormatted))")
        if let age = detail.ageOfMoney {
            lines.append("- Age of Money: \(age) days")
        }
        if let note = detail.note, !note.isEmpty {
            lines.append("- Note: \(note)")
        }
        lines.append("\n## Categories\n")
        lines.append("| Category | ID | Assigned | Activity | Available |")
        lines.append("|----------|----|----------|----------|-----------|")
        for cat in detail.categories where !cat.deleted && !cat.hidden && !cat.internal {
            let cells = [
                esc(cat.name),
                "`\(cat.id)`",
                money(cat.budgeted, cat.budgetedFormatted),
                money(cat.activity, cat.activityFormatted),
                money(cat.balance, cat.balanceFormatted),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Transactions

    static let dateRangeProperties: [String: Value] = [
        "since_date": Schema.date("Only include transactions on or after this date"),
        "until_date": Schema.date("Only include transactions on or before this date"),
        "limit": Schema.integer(
            "Maximum rows to return, newest first (default \(defaultTransactionLimit))",
            minimum: 1,
            maximum: maxTransactionLimit
        ),
    ]

    static let listTransactions = ToolSpec(
        name: "list_transactions",
        title: "List transactions",
        description: "List transactions (newest first) with IDs, account, payee, category, amount, and status. Defaults to the last 30 days. Use type=unapproved or type=uncategorized to triage.",
        inputSchema: Schema.object(
            dateRangeProperties.merging([
                "plan_id": Schema.planId,
                "account_id": Schema.string("Only this account"),
                "days": Schema.integer("Days to look back when since_date is omitted (default 30)", minimum: 1),
                "type": Schema.string("Server-side filter", oneOf: ["unapproved", "uncategorized"]),
                "category_name": Schema.string("Only this category name (case-insensitive exact match)"),
            ]) { a, _ in a }
        ),
        annotations: readOnlyAnnotations
    ) { args, client in
        let days = args["days"]?.intValue ?? 30
        let since = try optionalDate(args, key: "since_date")
            ?? Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let until = try optionalDate(args, key: "until_date")
        let type = try parseTransactionType(args["type"]?.stringValue)
        let limit = try transactionLimit(args)
        let categoryFilter = args["category_name"]?.stringValue?.lowercased()

        var transactions = try await client.listTransactions(
            planId: planId(args, client: client),
            accountId: args["account_id"]?.stringValue,
            query: TransactionQuery(sinceDate: since, untilDate: until, type: type)
        ).filter { !$0.deleted }
        if let categoryFilter {
            transactions = transactions.filter { ($0.categoryName ?? "").lowercased() == categoryFilter }
        }

        let range = describeRange(since: since, until: until)
        let (rows, note) = applyLimit(transactions.sorted { $0.date > $1.date }, limit: limit)
        let title = "# Transactions \(range)\n" + note
        return textResult(Formatters.formatTransactionDetailTable(rows, title: title))
    }

    static let getTransaction = ToolSpec(
        name: "get_transaction",
        title: "Get transaction",
        description: "Full details for one transaction, including account, payee and category IDs, flag, memo, and split lines.",
        inputSchema: Schema.object(
            ["plan_id": Schema.planId, "transaction_id": Schema.string("Transaction ID")],
            required: ["transaction_id"]
        ),
        annotations: readOnlyAnnotations
    ) { args, client in
        let txn = try await client.getTransaction(
            planId: planId(args, client: client),
            transactionId: try requireString(args, key: "transaction_id")
        )
        return textResult(Formatters.formatTransactionDetail(txn))
    }

    static let getTransactionsByPayee = ToolSpec(
        name: "get_transactions_by_payee",
        title: "Transactions by payee",
        description: "Transaction history for one payee (newest first), optionally limited to a date range.",
        inputSchema: Schema.object(
            dateRangeProperties.merging([
                "plan_id": Schema.planId,
                "payee_id": Schema.string("Payee ID (see list_payees)"),
            ]) { a, _ in a },
            required: ["payee_id"]
        ),
        annotations: readOnlyAnnotations
    ) { args, client in
        let transactions = try await client.transactionsByPayee(
            planId: planId(args, client: client),
            payeeId: try requireString(args, key: "payee_id"),
            query: try hybridQuery(args)
        )
        return try hybridResult(transactions, title: "Transactions for payee", args: args)
    }

    static let getTransactionsByCategory = ToolSpec(
        name: "get_transactions_by_category",
        title: "Transactions by category",
        description: "Transaction history for one category (newest first), optionally limited to a date range. Split lines in the category are included.",
        inputSchema: Schema.object(
            dateRangeProperties.merging([
                "plan_id": Schema.planId,
                "category_id": Schema.string("Category ID (see list_categories)"),
            ]) { a, _ in a },
            required: ["category_id"]
        ),
        annotations: readOnlyAnnotations
    ) { args, client in
        let transactions = try await client.transactionsByCategory(
            planId: planId(args, client: client),
            categoryId: try requireString(args, key: "category_id"),
            query: try hybridQuery(args)
        )
        return try hybridResult(transactions, title: "Transactions for category", args: args)
    }

    static func hybridQuery(_ args: [String: Value]) throws -> TransactionQuery {
        TransactionQuery(
            sinceDate: try optionalDate(args, key: "since_date"),
            untilDate: try optionalDate(args, key: "until_date")
        )
    }

    static func hybridResult(
        _ transactions: [HybridTransaction],
        title: String,
        args: [String: Value]
    ) throws -> CallTool.Result {
        let active = transactions.filter { !$0.deleted }.sorted { $0.date > $1.date }
        let range = describeRange(
            since: try optionalDate(args, key: "since_date"),
            until: try optionalDate(args, key: "until_date")
        )
        let (rows, note) = applyLimit(active, limit: try transactionLimit(args))
        return textResult(Formatters.formatHybridTransactionTable(rows, title: "# \(title) \(range)\n" + note))
    }

    static func parseTransactionType(_ string: String?) throws -> TransactionType? {
        guard let string else { return nil }
        guard let type = TransactionType(rawValue: string.lowercased()) else {
            throw YNABMCPError.invalidParameter("type", detail: "'\(string)' is not one of unapproved, uncategorized")
        }
        return type
    }

    static func transactionLimit(_ args: [String: Value]) throws -> Int {
        try boundedLimit(args, default: defaultTransactionLimit, max: maxTransactionLimit)
    }

    static func boundedLimit(_ args: [String: Value], default defaultValue: Int, max: Int) throws -> Int {
        guard let value = args["limit"] else { return defaultValue }
        guard let limit = value.intValue, (1...max).contains(limit) else {
            throw YNABMCPError.invalidParameter("limit", detail: "must be an integer from 1 to \(max)")
        }
        return limit
    }

    static func applyLimit<T>(_ rows: [T], limit: Int) -> ([T], String) {
        guard rows.count > limit else { return (rows, "") }
        let note = "Showing the newest \(limit) of \(rows.count) transactions. Narrow the date range or raise `limit` to see more.\n"
        return (Array(rows.prefix(limit)), note)
    }

    static func describeRange(since: Date?, until: Date?) -> String {
        let format: (Date) -> String = { $0.formatted(.iso8601.year().month().day()) }
        switch (since, until) {
        case let (since?, until?): return "from \(format(since)) to \(format(until))"
        case let (since?, nil): return "since \(format(since))"
        case let (nil, until?): return "through \(format(until))"
        case (nil, nil): return "(all dates)"
        }
    }

    // MARK: - Payees

    static let listPayees = ToolSpec(
        name: "list_payees",
        title: "List payees",
        description: "List payees with IDs, alphabetically. Plans often have thousands of payees, so pass name_contains to find specific ones. Transfer payees (which move money between accounts) are marked.",
        inputSchema: Schema.object([
            "plan_id": Schema.planId,
            "name_contains": Schema.string("Only payees whose name contains this text (case-insensitive)"),
            "limit": Schema.integer(
                "Maximum rows to return (default \(defaultPayeeLimit))",
                minimum: 1,
                maximum: maxPayeeLimit
            ),
        ]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let filter = args["name_contains"]?.stringValue?.lowercased()
        let limit = try boundedLimit(args, default: defaultPayeeLimit, max: maxPayeeLimit)
        let payees = try await client.listPayees(planId: planId(args, client: client))
            .filter { !$0.deleted }
            .filter { filter == nil || $0.name.lowercased().contains(filter!) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let esc = Formatters.escapeTableCell

        var lines: [String] = ["# Payees\n"]
        if payees.count > limit {
            lines.append("Showing the first \(limit) of \(payees.count) payees. Use name_contains to narrow the list.\n")
        }
        lines += ["| Name | ID |", "|------|----|"]
        for payee in payees.prefix(limit) {
            let suffix = payee.transferAccountId != nil ? " (transfer)" : ""
            lines.append("| \(esc(payee.name))\(suffix) | `\(payee.id)` |")
        }
        lines.append("\nTotal: \(payees.count) payees")
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Scheduled

    static let listScheduledTransactions = ToolSpec(
        name: "list_scheduled_transactions",
        title: "List scheduled transactions",
        description: "List scheduled (recurring and future) transactions with payee, amount, frequency, next date, account, and category.",
        inputSchema: Schema.object(["plan_id": Schema.planId]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let scheduled = try await client.listScheduledTransactions(planId: planId(args, client: client))
            .filter { !$0.deleted }
            .sorted { $0.dateNext < $1.dateNext }
        let esc = Formatters.escapeTableCell

        var lines: [String] = ["# Scheduled Transactions\n"]
        if scheduled.isEmpty {
            lines.append("No scheduled transactions found.")
        } else {
            lines.append("| ID | Next Date | Frequency | Payee | Amount | Account | Category |")
            lines.append("|----|-----------|-----------|-------|--------|---------|----------|")
            for txn in scheduled {
                let cells = [
                    "`\(txn.id)`",
                    txn.dateNext,
                    txn.frequency.rawValue,
                    esc(txn.payeeName ?? "-"),
                    Formatters.money(txn.amount, formatted: txn.amountFormatted),
                    esc(txn.accountName),
                    esc(txn.categoryName ?? "-"),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("\nTotal: \(scheduled.count) scheduled transactions")
        return textResult(lines.joined(separator: "\n"))
    }
}
