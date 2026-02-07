import Foundation
import SwiftYNAB

public enum Formatters {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    /// Convert YNAB milliunits (1000 = $1.00) to dollar string like "$1,234.56"
    public static func dollars(from milliunits: Int) -> String {
        let amount = Double(milliunits) / 1000.0
        return currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// Convert dollar amount (e.g. 12.50) to YNAB milliunits (12500)
    public static func milliunits(from dollars: Double) -> Int {
        Int((dollars * 1000).rounded())
    }

    /// Escape pipe characters for markdown table cells
    public static func escapeTableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Format a Date as YYYY-MM-DD string
    public static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    // MARK: - Transaction Table Formatters

    /// Format an array of TransactionDetail into a markdown table
    public static func formatTransactionDetailTable(_ transactions: [TransactionDetail], title: String) -> String {
        let esc = escapeTableCell
        var lines: [String] = [title]
        if transactions.isEmpty {
            lines.append("No transactions found.")
        } else {
            lines.append("| ID | Date | Payee | Category | Amount | Cleared | Approved | Memo |")
            lines.append("|----|------|-------|----------|--------|---------|----------|------|")
            for txn in transactions {
                let id = "`\(txn.id)`"
                let date = txn.date
                let payee = esc(txn.payeeName ?? "-")
                let category = esc(txn.categoryName ?? "-")
                let amount = dollars(from: txn.amount)
                let cleared = String(describing: txn.cleared)
                let approved = txn.approved ? "Yes" : "No"
                let memo = esc(txn.memo ?? "")
                lines.append("| \(id) | \(date) | \(payee) | \(category) | \(amount) | \(cleared) | \(approved) | \(memo) |")
            }
        }
        lines.append("\nTotal: \(transactions.count) transactions")
        return lines.joined(separator: "\n")
    }

    /// Format an array of HybridTransaction into a markdown table (includes Account column)
    public static func formatHybridTransactionTable(_ transactions: [HybridTransaction], title: String) -> String {
        let esc = escapeTableCell
        var lines: [String] = [title]
        if transactions.isEmpty {
            lines.append("No transactions found.")
        } else {
            lines.append("| ID | Date | Account | Payee | Category | Amount | Cleared | Approved | Memo |")
            lines.append("|----|------|---------|-------|----------|--------|---------|----------|------|")
            for txn in transactions {
                let id = "`\(txn.id)`"
                let date = txn.date
                let account = esc(txn.accountName)
                let payee = esc(txn.payeeName ?? "-")
                let category = esc(txn.categoryName)
                let amount = dollars(from: txn.amount)
                let cleared = String(describing: txn.cleared)
                let approved = txn.approved ? "Yes" : "No"
                let memo = esc(txn.memo ?? "")
                lines.append("| \(id) | \(date) | \(account) | \(payee) | \(category) | \(amount) | \(cleared) | \(approved) | \(memo) |")
            }
        }
        lines.append("\nTotal: \(transactions.count) transactions")
        return lines.joined(separator: "\n")
    }

    /// Format a single TransactionDetail with all fields
    public static func formatTransactionDetail(_ txn: TransactionDetail) -> String {
        var lines: [String] = ["# Transaction\n"]
        lines.append("- **ID**: `\(txn.id)`")
        lines.append("- **Date**: \(txn.date)")
        lines.append("- **Amount**: \(dollars(from: txn.amount))")
        lines.append("- **Account**: \(txn.accountName)")
        if let payee = txn.payeeName {
            lines.append("- **Payee**: \(payee)")
        }
        if let category = txn.categoryName {
            lines.append("- **Category**: \(category)")
        }
        lines.append("- **Cleared**: \(txn.cleared)")
        lines.append("- **Approved**: \(txn.approved ? "Yes" : "No")")
        if let flagColor = txn.flagColor, flagColor != .none {
            lines.append("- **Flag**: \(flagColor.rawValue)")
        }
        if let memo = txn.memo, !memo.isEmpty {
            lines.append("- **Memo**: \(memo)")
        }
        return lines.joined(separator: "\n")
    }
}
