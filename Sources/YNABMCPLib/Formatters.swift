import Foundation
import SwiftYNAB

public enum Formatters {
    private static let fallbackFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 3
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// Display an amount. Prefers YNAB's own `*_formatted` string (which uses the plan's
    /// currency settings) and falls back to a plain number when YNAB didn't send one.
    public static func money(_ milliunits: Int, formatted: String? = nil) -> String {
        if let formatted, !formatted.isEmpty {
            return formatted
        }
        let amount = Double(milliunits) / 1000.0
        return fallbackFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    /// Convert a currency amount (e.g. 12.50) to YNAB milliunits (12500).
    public static func milliunits(from amount: Double) -> Int {
        Int((amount * 1000).rounded())
    }

    /// Escape characters that break markdown table cells.
    public static func escapeTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Transaction Tables

    public static func formatTransactionDetailTable(_ transactions: [TransactionDetail], title: String) -> String {
        let esc = escapeTableCell
        var lines: [String] = [title]
        if transactions.isEmpty {
            lines.append("No transactions found.")
        } else {
            lines.append("| ID | Date | Account | Payee | Category | Amount | Cleared | Approved | Memo |")
            lines.append("|----|------|---------|-------|----------|--------|---------|----------|------|")
            for txn in transactions {
                let category = txn.subtransactions.isEmpty ? (txn.categoryName ?? "-") : "Split (\(txn.subtransactions.count))"
                let cells = [
                    "`\(txn.id)`",
                    txn.date,
                    esc(txn.accountName),
                    esc(txn.payeeName ?? "-"),
                    esc(category),
                    money(txn.amount, formatted: txn.amountFormatted),
                    txn.cleared.rawValue,
                    txn.approved ? "Yes" : "No",
                    esc(txn.memo ?? ""),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("\nTotal: \(transactions.count) transactions")
        return lines.joined(separator: "\n")
    }

    public static func formatHybridTransactionTable(_ transactions: [HybridTransaction], title: String) -> String {
        let esc = escapeTableCell
        var lines: [String] = [title]
        if transactions.isEmpty {
            lines.append("No transactions found.")
        } else {
            lines.append("| ID | Date | Account | Payee | Category | Amount | Cleared | Approved | Memo |")
            lines.append("|----|------|---------|-------|----------|--------|---------|----------|------|")
            for txn in transactions {
                // Subtransactions of a split carry the parent ID; show it so updates target the parent.
                let id = txn.parentTransactionId.map { "`\($0)` (split part)" } ?? "`\(txn.id)`"
                let cells = [
                    id,
                    txn.date,
                    esc(txn.accountName),
                    esc(txn.payeeName ?? "-"),
                    esc(txn.categoryName ?? "-"),
                    money(txn.amount, formatted: txn.amountFormatted),
                    txn.cleared.rawValue,
                    txn.approved ? "Yes" : "No",
                    esc(txn.memo ?? ""),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("\nTotal: \(transactions.count) transactions")
        return lines.joined(separator: "\n")
    }

    public static func formatTransactionDetail(_ txn: TransactionDetail, heading: String = "Transaction") -> String {
        var lines: [String] = ["# \(heading)\n"]
        lines.append("- **ID**: `\(txn.id)`")
        lines.append("- **Date**: \(txn.date)")
        lines.append("- **Amount**: \(money(txn.amount, formatted: txn.amountFormatted))")
        lines.append("- **Account**: \(txn.accountName) (`\(txn.accountId)`)")
        if let payee = txn.payeeName {
            let id = txn.payeeId.map { " (`\($0)`)" } ?? ""
            lines.append("- **Payee**: \(payee)\(id)")
        }
        if let category = txn.categoryName {
            let id = txn.categoryId.map { " (`\($0)`)" } ?? ""
            lines.append("- **Category**: \(category)\(id)")
        }
        if txn.transferAccountId != nil {
            lines.append("- **Transfer**: yes")
        }
        lines.append("- **Cleared**: \(txn.cleared.rawValue)")
        lines.append("- **Approved**: \(txn.approved ? "Yes" : "No")")
        if let flagColor = txn.flagColor, flagColor != .none {
            let name = txn.flagName.map { " (\($0))" } ?? ""
            lines.append("- **Flag**: \(flagColor.rawValue)\(name)")
        }
        if let memo = txn.memo, !memo.isEmpty {
            lines.append("- **Memo**: \(memo)")
        }
        if let importPayee = txn.importPayeeNameOriginal, !importPayee.isEmpty {
            lines.append("- **Imported payee**: \(importPayee)")
        }
        let parts = txn.subtransactions.filter { !$0.deleted }
        if !parts.isEmpty {
            lines.append("\n## Split\n")
            for sub in parts {
                let category = sub.categoryName ?? "-"
                let memo = sub.memo.map { " (\($0))" } ?? ""
                lines.append("- \(money(sub.amount, formatted: sub.amountFormatted)): \(category)\(memo)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
