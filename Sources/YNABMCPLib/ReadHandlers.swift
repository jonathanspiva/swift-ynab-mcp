import Foundation
import MCP
import SwiftYNAB

// MARK: - Read Handler Implementations

extension ToolHandlers {

    static func handleListBudgets(client: YNABClient) async throws -> CallTool.Result {
        let budgets = try await client.listBudgets()

        var lines: [String] = ["# YNAB Budgets\n"]
        for budget in budgets {
            let currency = budget.currencyFormat?.isoCode ?? "USD"
            lines.append("- **\(budget.name)** (\(currency))")
            lines.append("  ID: `\(budget.id)`")
            if let lastModified = budget.lastModifiedOn {
                lines.append("  Last modified: \(lastModified)")
            }
            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleListAccounts(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let accounts = try await client.listAccounts(budgetId: budgetId)

        var lines: [String] = ["# Accounts\n"]
        for account in accounts where !account.deleted {
            let status = account.closed ? " (CLOSED)" : ""
            let balance = Formatters.dollars(from: account.balance)
            lines.append("- **\(account.name)**\(status) - \(balance)")
            lines.append("  Type: \(account.type)  |  On budget: \(account.onBudget ? "Yes" : "No")")
            lines.append("  Cleared: \(Formatters.dollars(from: account.clearedBalance))  |  Uncleared: \(Formatters.dollars(from: account.unclearedBalance))")
            lines.append("  ID: `\(account.id)`")
            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleGetBudgetSummary(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let detail = try await client.getBudgetDetail(budgetId: budgetId)

        var lines: [String] = ["# Budget: \(detail.name)\n"]

        lines.append("## Accounts\n")
        for account in detail.accounts where !account.deleted && !account.closed {
            lines.append("- **\(account.name)**: \(Formatters.dollars(from: account.balance))")
        }
        lines.append("")

        lines.append("## Category Groups\n")
        for group in detail.categoryGroups where !group.deleted && !group.hidden {
            lines.append("### \(group.name)")
            let groupCategories = detail.categories.filter {
                $0.categoryGroupId == group.id && !$0.deleted && !$0.hidden
            }
            for cat in groupCategories {
                let budgeted = Formatters.dollars(from: cat.budgeted)
                let activity = Formatters.dollars(from: cat.activity)
                let balance = Formatters.dollars(from: cat.balance)
                lines.append("- \(cat.name): Budgeted \(budgeted) | Activity \(activity) | Available \(balance)")
            }
            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleListCategories(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let groups = try await client.listCategories(budgetId: budgetId)

        var lines: [String] = ["# Categories\n"]
        for group in groups where !group.deleted && !group.hidden {
            lines.append("## \(group.name)")
            for cat in group.categories where !cat.deleted && !cat.hidden {
                lines.append("- **\(cat.name)** `\(cat.id)`")
            }
            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleListRecentTransactions(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let accountId = args["account_id"]?.stringValue
        let days = args["days"]?.intValue ?? 30
        let categoryFilter = args["category_name"]?.stringValue?.lowercased()
        let approvedFilter = args["approved"]?.boolValue
        let untilDateStr = args["until_date"]?.stringValue

        let sinceDate: Date?
        if let sinceDateStr = args["since_date"]?.stringValue {
            sinceDate = parseDate(sinceDateStr)
        } else {
            sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        }

        let transactions = try await client.listTransactions(
            budgetId: budgetId,
            accountId: accountId,
            sinceDate: sinceDate
        )

        var filtered = transactions.filter { !$0.deleted }
        if let categoryFilter {
            filtered = filtered.filter { ($0.categoryName ?? "").lowercased() == categoryFilter }
        }
        if let approvedFilter {
            filtered = filtered.filter { $0.approved == approvedFilter }
        }
        if let untilDateStr, let untilDate = parseDate(untilDateStr) {
            let untilStr = Formatters.dateString(from: untilDate)
            filtered = filtered.filter { $0.date <= untilStr }
        }

        let title: String
        if let sinceDateStr = args["since_date"]?.stringValue {
            if let untilDateStr {
                title = "# Transactions from \(sinceDateStr) to \(untilDateStr)\n"
            } else {
                title = "# Transactions since \(sinceDateStr)\n"
            }
        } else {
            title = "# Recent Transactions (last \(days) days)\n"
        }

        return CallTool.Result(content: [.text(Formatters.formatTransactionDetailTable(filtered, title: title))])
    }

    static func handleGetMonthSummary(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let month = try requireString(args, key: "month")

        let monthDetail = try await client.getMonth(budgetId: budgetId, month: month)
        let esc = Formatters.escapeTableCell

        var lines: [String] = ["# Month: \(month)\n"]
        lines.append("- Income: \(Formatters.dollars(from: monthDetail.income))")
        lines.append("- Budgeted: \(Formatters.dollars(from: monthDetail.budgeted))")
        lines.append("- Activity: \(Formatters.dollars(from: monthDetail.activity))")
        lines.append("- To Be Budgeted: \(Formatters.dollars(from: monthDetail.toBeBudgeted))")
        if let age = monthDetail.ageOfMoney {
            lines.append("- Age of Money: \(age) days")
        }
        lines.append("")

        lines.append("## Categories\n")
        lines.append("| Category | Budgeted | Activity | Available |")
        lines.append("|----------|----------|----------|-----------|")
        for cat in monthDetail.categories where !cat.deleted && !cat.hidden {
            let name = esc(cat.name)
            let budgeted = Formatters.dollars(from: cat.budgeted)
            let activity = Formatters.dollars(from: cat.activity)
            let balance = Formatters.dollars(from: cat.balance)
            lines.append("| \(name) | \(budgeted) | \(activity) | \(balance) |")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleGetTransaction(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let transactionId = try requireString(args, key: "transaction_id")

        let txn = try await client.getTransaction(budgetId: budgetId, transactionId: transactionId)

        return CallTool.Result(content: [.text(Formatters.formatTransactionDetail(txn))])
    }

    static func handleListPayees(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let payees = try await client.listPayees(budgetId: budgetId)
        let esc = Formatters.escapeTableCell

        var lines: [String] = ["# Payees\n"]
        lines.append("| Name | ID |")
        lines.append("|------|----|")
        for payee in payees where !payee.deleted {
            let suffix = payee.transferAccountId != nil ? " (transfer)" : ""
            lines.append("| \(esc(payee.name))\(suffix) | `\(payee.id)` |")
        }
        lines.append("\nTotal: \(payees.filter { !$0.deleted }.count) payees")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }

    static func handleGetTransactionsByPayee(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let payeeId = try requireString(args, key: "payee_id")
        let sinceDate = parseDate(args["since_date"]?.stringValue)
        let untilDateStr = args["until_date"]?.stringValue

        var transactions = try await client.transactionsByPayee(
            budgetId: budgetId,
            payeeId: payeeId,
            sinceDate: sinceDate
        )

        transactions = transactions.filter { !$0.deleted }
        if let untilDateStr, let untilDate = parseDate(untilDateStr) {
            let untilStr = Formatters.dateString(from: untilDate)
            transactions = transactions.filter { $0.date <= untilStr }
        }

        let title = "# Transactions for Payee\n"
        return CallTool.Result(content: [.text(Formatters.formatHybridTransactionTable(transactions, title: title))])
    }

    static func handleGetTransactionsByCategory(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let categoryId = try requireString(args, key: "category_id")
        let sinceDate = parseDate(args["since_date"]?.stringValue)
        let untilDateStr = args["until_date"]?.stringValue

        var transactions = try await client.transactionsByCategory(
            budgetId: budgetId,
            categoryId: categoryId,
            sinceDate: sinceDate
        )

        transactions = transactions.filter { !$0.deleted }
        if let untilDateStr, let untilDate = parseDate(untilDateStr) {
            let untilStr = Formatters.dateString(from: untilDate)
            transactions = transactions.filter { $0.date <= untilStr }
        }

        let title = "# Transactions for Category\n"
        return CallTool.Result(content: [.text(Formatters.formatHybridTransactionTable(transactions, title: title))])
    }

    static func handleListScheduledTransactions(
        args: [String: Value],
        client: YNABClient
    ) async throws -> CallTool.Result {
        let budgetId = try requireString(args, key: "budget_id")
        let transactions = try await client.listScheduledTransactions(budgetId: budgetId)
        let esc = Formatters.escapeTableCell

        var lines: [String] = ["# Scheduled Transactions\n"]
        let active = transactions.filter { !$0.deleted }
        if active.isEmpty {
            lines.append("No scheduled transactions found.")
        } else {
            lines.append("| Payee | Amount | Frequency | Next Date | Account | Category |")
            lines.append("|-------|--------|-----------|-----------|---------|----------|")
            for txn in active {
                let payee = esc(txn.payeeName)
                let amount = Formatters.dollars(from: txn.amount)
                let frequency = txn.frequency
                let nextDate = txn.dateNext
                let account = esc(txn.accountName)
                let category = esc(txn.categoryName ?? "-")
                lines.append("| \(payee) | \(amount) | \(frequency) | \(nextDate) | \(account) | \(category) |")
            }
        }
        lines.append("\nTotal: \(active.count) scheduled transactions")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
