import Foundation
import SwiftYNAB

/// One categorized money movement for reporting: a transaction, or one line of a split.
public struct ReportLine: Equatable, Sendable {
    public var date: String
    public var amount: Int
    public var categoryId: String?
    public var categoryName: String
    public var payeeName: String

    public init(date: String, amount: Int, categoryId: String? = nil, categoryName: String, payeeName: String) {
        self.date = date
        self.amount = amount
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.payeeName = payeeName
    }
}

public enum ReportGrouping: String, CaseIterable, Sendable {
    case category
    case categoryGroup = "category_group"
    case payee
    case month
}

public struct ReportRow: Equatable, Sendable {
    public var key: String
    public var outflow: Int = 0
    public var inflow: Int = 0
    public var count: Int = 0
    public var net: Int { outflow + inflow }
}

public struct SpendingReport: Equatable, Sendable {
    public var rows: [ReportRow]
    /// Inflows to Ready to Assign in the range, reported separately from spending.
    public var income: Int
    public var totalOutflow: Int { rows.reduce(0) { $0 + $1.outflow } }
    public var totalInflow: Int { rows.reduce(0) { $0 + $1.inflow } }
    public var totalNet: Int { totalOutflow + totalInflow }
}

public enum Reports {
    static let uncategorized = "Uncategorized"

    /// Flatten transactions into report lines. Splits become one line per part. Tracking accounts
    /// (not in `onBudgetAccountIds`) are skipped, and so are uncategorized transfers, which just
    /// move money between budget accounts.
    public static func lines(from transactions: [TransactionDetail], onBudgetAccountIds: Set<String>) -> [ReportLine] {
        var result: [ReportLine] = []
        for txn in transactions where !txn.deleted && onBudgetAccountIds.contains(txn.accountId) {
            let parts = txn.subtransactions.filter { !$0.deleted }
            if parts.isEmpty {
                if txn.transferAccountId != nil && txn.categoryId == nil { continue }
                result.append(ReportLine(
                    date: txn.date,
                    amount: txn.amount,
                    categoryId: txn.categoryId,
                    categoryName: txn.categoryName ?? uncategorized,
                    payeeName: txn.payeeName ?? "-"
                ))
            } else {
                for part in parts {
                    if part.transferAccountId != nil && part.categoryId == nil { continue }
                    result.append(ReportLine(
                        date: txn.date,
                        amount: part.amount,
                        categoryId: part.categoryId,
                        categoryName: part.categoryName ?? uncategorized,
                        payeeName: part.payeeName ?? txn.payeeName ?? "-"
                    ))
                }
            }
        }
        return result
    }

    static func isIncome(_ line: ReportLine) -> Bool {
        line.categoryName.lowercased().hasPrefix("inflow:")
    }

    /// Group lines. Income (Inflow: Ready to Assign) is totalled separately, not as a spending row.
    /// Rows are sorted by biggest net spending first, or chronologically when grouped by month.
    public static func spending(
        _ lines: [ReportLine],
        groupBy: ReportGrouping,
        groupNames: [String: String] = [:]
    ) -> SpendingReport {
        var rows: [String: ReportRow] = [:]
        var income = 0
        for line in lines {
            if isIncome(line) {
                income += line.amount
                continue
            }
            let key: String
            switch groupBy {
            case .category: key = line.categoryName
            case .payee: key = line.payeeName
            case .month: key = String(line.date.prefix(7))
            case .categoryGroup:
                key = line.categoryId.flatMap { groupNames[$0] } ?? (line.categoryName == uncategorized ? uncategorized : "Other")
            }
            var row = rows[key] ?? ReportRow(key: key)
            if line.amount < 0 { row.outflow += line.amount } else { row.inflow += line.amount }
            row.count += 1
            rows[key] = row
        }
        let sorted = rows.values.sorted { a, b in
            if groupBy == .month { return a.key < b.key }
            return a.net == b.net ? a.key < b.key : a.net < b.net
        }
        return SpendingReport(rows: sorted, income: income)
    }

    /// Months in [since, until], both YYYY-MM-01, oldest first. Lexical comparison works for ISO dates.
    public static func months(_ months: [MonthSummary], since: String, until: String) -> [MonthSummary] {
        months
            .filter { !$0.deleted && $0.month >= since && $0.month <= until }
            .sorted { $0.month < $1.month }
    }

    /// First day of the month `offset` months from `date`, as YYYY-MM-01 (local time zone, like `parseDate`).
    public static func monthStart(_ date: Date, offset: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let shifted = calendar.date(byAdding: .month, value: offset, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month], from: shifted)
        return String(format: "%04d-%02d-01", parts.year ?? 1970, parts.month ?? 1)
    }
}
