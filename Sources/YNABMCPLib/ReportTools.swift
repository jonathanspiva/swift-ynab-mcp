import Foundation
import MCP
import SwiftYNAB

extension ToolHandlers {

    static let defaultReportRows = 50

    static let reportSpecs: [ToolSpec] = [spendingReport, monthlyTrends]

    static let spendingReport = ToolSpec(
        name: "spending_report",
        title: "Spending report",
        description: "Spending over a date range grouped by category, category_group, payee, or month, with outflow, inflow (refunds), net, and share of spending. Splits are broken out by line; transfers between budget accounts and tracking-account activity are excluded; income to Ready to Assign is shown separately. Defaults to the current month by category. Uses 2-3 API requests.",
        inputSchema: Schema.object([
            "plan_id": Schema.planId,
            "since_date": Schema.date("Start of the range (default: first day of the current month)"),
            "until_date": Schema.date("End of the range (default: today)"),
            "group_by": Schema.string("How to group (default category)", oneOf: ReportGrouping.allCases.map(\.rawValue)),
            "account_id": Schema.string("Only this account"),
            "limit": Schema.integer("Maximum rows (default \(defaultReportRows)); the rest are summed into one line", minimum: 1, maximum: 500),
        ]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        let since = try optionalDate(args, key: "since_date") ?? parseDate(Reports.monthStart(Date()))!
        let until = try optionalDate(args, key: "until_date")
        let limit = try boundedLimit(args, default: defaultReportRows, max: 500)
        let rawGroup = args["group_by"]?.stringValue ?? ReportGrouping.category.rawValue
        guard let groupBy = ReportGrouping(rawValue: rawGroup) else {
            throw YNABMCPError.invalidParameter(
                "group_by", detail: "'\(rawGroup)' is not one of \(ReportGrouping.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        async let transactionsTask = client.listTransactions(
            planId: planId,
            accountId: args["account_id"]?.stringValue,
            query: TransactionQuery(sinceDate: since, untilDate: until)
        )
        async let accountsTask = client.listAccounts(planId: planId)
        let (transactions, accounts) = try await (transactionsTask, accountsTask)

        var groupNames: [String: String] = [:]
        if groupBy == .categoryGroup {
            for group in try await client.listCategories(planId: planId) {
                for category in group.categories { groupNames[category.id] = group.name }
            }
        }

        let onBudget = Set(accounts.filter(\.onBudget).map(\.id))
        let report = Reports.spending(
            Reports.lines(from: transactions, onBudgetAccountIds: onBudget),
            groupBy: groupBy,
            groupNames: groupNames
        )
        let title = "# Spending by \(groupBy.rawValue.replacingOccurrences(of: "_", with: " ")) \(describeRange(since: since, until: until))\n"
        return textResult(formatSpendingReport(report, title: title, limit: limit))
    }

    static func formatSpendingReport(_ report: SpendingReport, title: String, limit: Int) -> String {
        let money = { (value: Int) in Formatters.money(value) }
        let esc = Formatters.escapeTableCell
        // Share of spending among rows that net to spending; rows with net inflow (e.g. reimbursements) show "-".
        let spent = report.rows.reduce(0) { $0 + max(0, -$1.net) }
        let share = { (row: ReportRow) -> String in
            guard spent > 0, row.net < 0 else { return "-" }
            return String(format: "%.1f%%", Double(-row.net) / Double(spent) * 100)
        }

        var lines = [title]
        lines.append("- **Spent**: \(money(report.totalOutflow))")
        lines.append("- **Refunds and other inflows**: \(money(report.totalInflow))")
        lines.append("- **Net spending**: \(money(report.totalNet))")
        lines.append("- **Income (Ready to Assign)**: \(money(report.income))")
        lines.append("")
        if report.rows.isEmpty {
            lines.append("No spending found.")
            return lines.joined(separator: "\n")
        }
        lines.append("| Group | Outflow | Inflow | Net | Share | Txns |")
        lines.append("|-------|---------|--------|-----|-------|------|")
        var shown = Array(report.rows.prefix(limit))
        let rest = report.rows.dropFirst(limit)
        if !rest.isEmpty {
            var other = ReportRow(key: "(\(rest.count) more)")
            for row in rest {
                other.outflow += row.outflow
                other.inflow += row.inflow
                other.count += row.count
            }
            shown.append(other)
        }
        for row in shown {
            let cells = [esc(row.key), money(row.outflow), money(row.inflow), money(row.net), share(row), String(row.count)]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    static let monthlyTrends = ToolSpec(
        name: "monthly_trends",
        title: "Monthly trends",
        description: "Month-by-month income, assigned, activity (spending), Ready to Assign, and age of money, with averages. One API request covers any range. Defaults to the last 12 months.",
        inputSchema: Schema.object([
            "plan_id": Schema.planId,
            "since_month": Schema.string("First month as YYYY-MM-01 (default: 11 months before the current month)"),
            "until_month": Schema.string("Last month as YYYY-MM-01 (default: the current month)"),
        ]),
        annotations: readOnlyAnnotations
    ) { args, client in
        let now = Date()
        let since = args["since_month"] == nil ? Reports.monthStart(now, offset: -11) : try requireMonth(args, key: "since_month")
        let until = args["until_month"] == nil ? Reports.monthStart(now) : try requireMonth(args, key: "until_month")
        let resolve = { (value: String) in value == "current" ? Reports.monthStart(now) : value }

        let months = Reports.months(
            try await client.listMonths(planId: planId(args, client: client)),
            since: resolve(since),
            until: resolve(until)
        )
        return textResult(formatMonthlyTrends(months, title: "# Monthly Trends \(resolve(since)) to \(resolve(until))\n"))
    }

    /// Uses plain numbers throughout (not YNAB's formatted strings) so computed columns and averages match.
    static func formatMonthlyTrends(_ months: [MonthSummary], title: String) -> String {
        let money = { (value: Int) in Formatters.money(value) }
        var lines = [title]
        guard !months.isEmpty else {
            lines.append("No months found in that range.")
            return lines.joined(separator: "\n")
        }
        lines.append("| Month | Income | Assigned | Activity | Net | Ready to Assign | Age of Money |")
        lines.append("|-------|--------|----------|----------|-----|-----------------|--------------|")
        for month in months {
            let cells = [
                String(month.month.prefix(7)),
                money(month.income),
                money(month.budgeted),
                money(month.activity),
                money(month.income + month.activity),
                money(month.toBeBudgeted),
                month.ageOfMoney.map { "\($0) days" } ?? "-",
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        let average = { (total: Int) in money(Formatters.roundToCents(total / months.count)) }
        let income = months.reduce(0) { $0 + $1.income }
        let activity = months.reduce(0) { $0 + $1.activity }
        lines.append("")
        lines.append("- **Average income**: \(average(income))")
        lines.append("- **Average activity**: \(average(activity))")
        lines.append("- **Average net**: \(average(income + activity))")
        return lines.joined(separator: "\n")
    }
}
