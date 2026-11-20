import Foundation
import Testing
import SwiftYNAB
@testable import YNABMCPLib

@Suite("Reports")
struct ReportsTests {

    static func txn(
        id: String = UUID().uuidString,
        date: String = "2026-11-03",
        amount: Int,
        account: String = "checking",
        payee: String? = "Store",
        categoryId: String? = "cat-groceries",
        category: String? = "Groceries",
        transferAccountId: String? = nil,
        cleared: ClearedStatus = .cleared,
        deleted: Bool = false,
        subtransactions: [SubTransaction] = []
    ) -> TransactionDetail {
        TransactionDetail(
            id: id, date: date, amount: amount, amountFormatted: nil, amountCurrency: nil,
            memo: nil, cleared: cleared, approved: true, flagColor: nil, flagName: nil,
            accountId: account, accountName: account, payeeId: nil, payeeName: payee,
            categoryId: categoryId, categoryName: category,
            transferAccountId: transferAccountId, transferTransactionId: nil, matchedTransactionId: nil,
            importId: nil, importPayeeName: nil, importPayeeNameOriginal: nil, debtTransactionType: nil,
            deleted: deleted, subtransactions: subtransactions
        )
    }

    static func sub(
        amount: Int,
        categoryId: String? = nil,
        category: String? = nil,
        payee: String? = nil,
        transferAccountId: String? = nil,
        deleted: Bool = false
    ) -> SubTransaction {
        SubTransaction(
            id: UUID().uuidString, transactionId: "parent", amount: amount, amountFormatted: nil,
            amountCurrency: nil, memo: nil, payeeId: nil, payeeName: payee,
            categoryId: categoryId, categoryName: category,
            transferAccountId: transferAccountId, transferTransactionId: nil, deleted: deleted
        )
    }

    static func month(_ month: String, income: Int = 0, activity: Int = 0, deleted: Bool = false) -> MonthSummary {
        MonthSummary(
            month: month, note: nil, income: income, incomeFormatted: nil, incomeCurrency: nil,
            budgeted: 0, budgetedFormatted: nil, budgetedCurrency: nil,
            activity: activity, activityFormatted: nil, activityCurrency: nil,
            toBeBudgeted: 0, toBeBudgetedFormatted: nil, toBeBudgetedCurrency: nil,
            ageOfMoney: nil, deleted: deleted
        )
    }

    // MARK: - lines(from:)

    @Test("Skips deleted, tracking-account, and uncategorized transfer transactions")
    func linesFiltering() {
        let lines = Reports.lines(from: [
            Self.txn(amount: -10_000),
            Self.txn(amount: -20_000, deleted: true),
            Self.txn(amount: -30_000, account: "vanguard"),
            Self.txn(amount: -40_000, categoryId: nil, category: nil, transferAccountId: "savings"),
            // A categorized transfer (to a tracking account) is real spending.
            Self.txn(amount: -50_000, categoryId: "cat-hsa", category: "Medical", transferAccountId: "hsa"),
        ], onBudgetAccountIds: ["checking"])
        #expect(lines.map(\.amount) == [-10_000, -50_000])
    }

    @Test("Splits become one line per part, inheriting the parent payee")
    func linesSplits() {
        let parent = Self.txn(
            amount: -2_700_000, payee: "Jovana", categoryId: nil, category: nil,
            subtransactions: [
                Self.sub(amount: -2_400_000, transferAccountId: "grom"),
                Self.sub(amount: -300_000, categoryId: "cat-cash", category: "Cash"),
                Self.sub(amount: -1, categoryId: "x", category: "Gone", deleted: true),
            ]
        )
        let lines = Reports.lines(from: [parent], onBudgetAccountIds: ["checking"])
        #expect(lines == [ReportLine(date: "2026-11-03", amount: -300_000, categoryId: "cat-cash", categoryName: "Cash", payeeName: "Jovana")])
    }

    @Test("Uncategorized non-transfers are labelled Uncategorized")
    func linesUncategorized() {
        let lines = Reports.lines(from: [Self.txn(amount: -1, categoryId: nil, category: nil)], onBudgetAccountIds: ["checking"])
        #expect(lines.first?.categoryName == "Uncategorized")
    }

    // MARK: - spending

    static let sample: [ReportLine] = [
        ReportLine(date: "2026-10-05", amount: -100_000, categoryId: "g", categoryName: "Groceries", payeeName: "Safeway"),
        ReportLine(date: "2026-10-20", amount: 20_000, categoryId: "g", categoryName: "Groceries", payeeName: "Safeway"),
        ReportLine(date: "2026-11-02", amount: -50_000, categoryId: "d", categoryName: "Dining", payeeName: "Ridge Cafe"),
        ReportLine(date: "2026-11-03", amount: -200_000, categoryId: "r", categoryName: "Rent", payeeName: "Landlord"),
        ReportLine(date: "2026-11-01", amount: 5_000_000, categoryId: "i", categoryName: "Inflow: Ready to Assign", payeeName: "Employer"),
    ]

    @Test("Groups by category, biggest net spending first, income separate")
    func spendingByCategory() {
        let report = Reports.spending(Self.sample, groupBy: .category)
        #expect(report.rows.map(\.key) == ["Rent", "Groceries", "Dining"])
        #expect(report.rows[1] == ReportRow(key: "Groceries", outflow: -100_000, inflow: 20_000, count: 2))
        #expect(report.income == 5_000_000)
        #expect(report.totalOutflow == -350_000)
        #expect(report.totalInflow == 20_000)
        #expect(report.totalNet == -330_000)
    }

    @Test("Groups by month chronologically")
    func spendingByMonth() {
        let report = Reports.spending(Self.sample, groupBy: .month)
        #expect(report.rows.map(\.key) == ["2026-10", "2026-11"])
        #expect(report.rows.map(\.net) == [-80_000, -250_000])
    }

    @Test("Groups by payee and by category group")
    func spendingByPayeeAndGroup() {
        #expect(Reports.spending(Self.sample, groupBy: .payee).rows.map(\.key) == ["Landlord", "Safeway", "Ridge Cafe"])
        let byGroup = Reports.spending(
            Self.sample,
            groupBy: .categoryGroup,
            groupNames: ["g": "Everyday", "d": "Everyday", "r": "Bills"]
        )
        #expect(byGroup.rows.map(\.key) == ["Bills", "Everyday"])
        #expect(byGroup.rows[1].net == -130_000)
    }

    @Test("Report text shows totals, share, and an overflow row")
    func formatReport() {
        let report = Reports.spending(Self.sample, groupBy: .category)
        let text = ToolHandlers.formatSpendingReport(report, title: "# Test\n", limit: 2)
        #expect(text.contains("| Rent | -200.00 | 0.00 | -200.00 | 60.6% | 1 |"))
        #expect(text.contains("(1 more)"))
        #expect(text.contains("**Income (Ready to Assign)**: 5,000.00"))
        #expect(!text.contains("| Dining |"))
    }

    @Test("Share ignores rows that net to an inflow, so shares sum to 100%")
    func shareIgnoresNetInflows() {
        let lines = Self.sample + [
            ReportLine(date: "2026-11-04", amount: 400_000, categoryId: "w", categoryName: "Work Expenses", payeeName: "Employer"),
        ]
        let text = ToolHandlers.formatSpendingReport(Reports.spending(lines, groupBy: .category), title: "", limit: 50)
        #expect(text.contains("| Rent | -200.00 | 0.00 | -200.00 | 60.6% | 1 |"))
        #expect(text.contains("| Work Expenses | 0.00 | 400.00 | 400.00 | - | 1 |"))
    }

    @Test("Monthly trends use one number format and round averages to cents")
    func monthlyTrendsFormat() {
        let text = ToolHandlers.formatMonthlyTrends([
            Self.month("2026-09-01", income: 100_705_130, activity: -107_244_890),
            Self.month("2026-10-01", income: 3_270_450, activity: -5_452_381),
            Self.month("2026-11-01", income: 0, activity: -1),
        ], title: "")
        #expect(text.contains("| 2026-09 | 100,705.13 | 0.00 | -107,244.89 | -6,539.76 |"))
        #expect(text.contains("**Average activity**: -37,565.76"))
        #expect(!text.contains("$"))
    }

    @Test("roundToCents rounds milliunits to whole cents")
    func roundToCents() {
        #expect(Formatters.roundToCents(-25_589_606) == -25_589_610)
        #expect(Formatters.roundToCents(1_234) == 1_230)
        #expect(Formatters.roundToCents(0) == 0)
    }

    // MARK: - Dates

    @Test("Dates round-trip through SwiftYNAB's query formatting without shifting a day")
    func datesMatchSwiftYNAB() {
        for day in ["2026-05-01", "2026-01-01", "2026-12-31", "2026-03-08", "2026-11-01"] {
            let date = ToolHandlers.parseDate(day)!
            #expect(DateConverter.iso8601DateString(from: date) == day, "since_date for \(day)")
            #expect(ToolHandlers.isoDay(date) == day)
        }
    }

    // MARK: - months

    @Test("months filters to the inclusive range and sorts oldest first")
    func monthsRange() {
        let months = Reports.months([
            Self.month("2026-12-01"),
            Self.month("2026-10-01"),
            Self.month("2026-09-01"),
            Self.month("2026-11-01", deleted: true),
            Self.month("2026-08-01"),
        ], since: "2026-09-01", until: "2026-12-01")
        #expect(months.map(\.month) == ["2026-09-01", "2026-10-01", "2026-12-01"])
    }

    @Test("monthStart handles offsets across year boundaries")
    func monthStart() {
        let date = ToolHandlers.parseDate("2026-11-19")!
        #expect(Reports.monthStart(date) == "2026-11-01")
        #expect(Reports.monthStart(date, offset: -11) == "2025-12-01")
        #expect(Reports.monthStart(date, offset: 2) == "2027-01-01")
    }

    // MARK: - Reconcile

    @Test("ReconcilePlan computes the adjustment and locks only cleared transactions")
    func reconcilePlan() {
        let plan = ReconcilePlan(
            clearedBalance: 3_535_130,
            statementBalance: 1_684_130,
            transactions: [
                Self.txn(id: "a", amount: -1, cleared: .cleared),
                Self.txn(id: "b", amount: -1, cleared: .uncleared),
                Self.txn(id: "c", amount: -1, cleared: .reconciled),
                Self.txn(id: "d", amount: -1, cleared: .cleared, deleted: true),
            ]
        )
        #expect(plan.adjustment == -1_851_000)
        #expect(plan.transactionIds == ["a"])
        #expect(ReconcilePlan(clearedBalance: 5, statementBalance: 5, transactions: []).adjustment == 0)
    }
}
