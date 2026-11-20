import Foundation
import MCP
import SwiftYNAB

/// Which of a payee's transactions can be moved to another payee.
public struct PayeeMergePlan: Equatable, Sendable {
    /// Whole transactions (not split lines), deduplicated, oldest first.
    public var movable: [HybridTransaction]
    /// Split lines carrying the payee. YNAB can't edit lines of an existing split, so these stay.
    public var splitLines: [HybridTransaction]

    public init(_ transactions: [HybridTransaction]) {
        var seen = Set<String>()
        var movable: [HybridTransaction] = []
        var splitLines: [HybridTransaction] = []
        for txn in transactions.sorted(by: { $0.date < $1.date }) where !txn.deleted {
            if txn.parentTransactionId != nil {
                splitLines.append(txn)
            } else if seen.insert(txn.id).inserted {
                movable.append(txn)
            }
        }
        self.movable = movable
        self.splitLines = splitLines
    }
}

extension ToolHandlers {

    static let maxMergeSources = 10

    static let mergePayees = ToolSpec(
        name: "merge_payees",
        title: "Merge payees",
        description: "Move every transaction from one or more payees to another existing payee (by ID, so duplicate names can't cause a mismatch). Unlike rename_payee, this actually combines them. Split lines and scheduled transactions are not moved and are reported instead. The emptied payees stay in the payee list; the API can't delete payees. Run with dry_run=true first. Costs 1 request per source payee plus 2.",
        inputSchema: Schema.object(
            [
                "plan_id": Schema.planId,
                "from_payee_ids": Schema.stringArray("Payee IDs to merge away (up to \(maxMergeSources); see list_payees)"),
                "to_payee_id": Schema.string("Payee ID to keep"),
                "dry_run": Schema.boolean("Only report what would move (default false)"),
            ],
            required: ["from_payee_ids", "to_payee_id"]
        ),
        annotations: updateAnnotations
    ) { args, client in
        let planId = planId(args, client: client)
        let fromIds = try requireStringArray(args, key: "from_payee_ids")
        let toId = try requireString(args, key: "to_payee_id")
        let dryRun = try optionalBool(args, key: "dry_run") ?? false
        try validateMergeIds(from: fromIds, to: toId)

        let payees = Dictionary(
            try await client.listPayees(planId: planId).filter { !$0.deleted }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let target = payees[toId] else {
            throw YNABMCPError.invalidParameter("to_payee_id", detail: "payee `\(toId)` was not found (see list_payees)")
        }
        for id in [toId] + fromIds {
            guard let payee = payees[id] else {
                throw YNABMCPError.invalidParameter("from_payee_ids", detail: "payee `\(id)` was not found (see list_payees)")
            }
            if payee.transferAccountId != nil {
                throw YNABMCPError.invalidParameter("from_payee_ids", detail: "'\(payee.name)' is a transfer payee and can't be merged")
            }
        }

        var all: [HybridTransaction] = []
        var counts: [(String, Int)] = []
        for id in fromIds {
            let transactions = try await client.transactionsByPayee(planId: planId, payeeId: id, query: TransactionQuery())
            all += transactions
            counts.append((payees[id]?.name ?? id, transactions.filter { !$0.deleted }.count))
        }
        let plan = PayeeMergePlan(all)

        var lines = [dryRun ? "# Merge Preview into \(target.name)\n" : "# Merged into \(target.name)\n"]
        for (name, count) in counts {
            lines.append("- **\(name)**: \(count) transaction\(count == 1 ? "" : "s")")
        }
        lines.append("- **Transactions to move**: \(plan.movable.count)")
        if !plan.splitLines.isEmpty {
            lines.append("- **Split lines left as is**: \(plan.splitLines.count) (YNAB can't edit lines of an existing split)")
        }

        if !dryRun && !plan.movable.isEmpty {
            let updates = plan.movable.map { TransactionChanges(payeeId: toId).save(id: $0.id) }
            let updated = try await client.updateTransactions(planId: planId, transactions: updates)
            lines.append("- **Moved**: \(updated.count) of \(plan.movable.count)")
            let missing = Set(plan.movable.map(\.id)).subtracting(updated.map(\.id))
            if !missing.isEmpty {
                lines.append("- **Not moved**: " + missing.sorted().map { "`\($0)`" }.joined(separator: ", "))
            }
        } else if dryRun {
            lines.append("\nDry run: nothing was changed.")
        }
        lines.append("\nScheduled transactions using the old payees are not changed; check list_scheduled_transactions.")
        lines.append("")
        lines.append(Formatters.formatHybridTransactionTable(
            plan.movable + plan.splitLines,
            title: dryRun ? "## Affected transactions\n" : "## Transactions\n"
        ))
        return textResult(lines.joined(separator: "\n"))
    }

    /// Checks that need no network: no duplicates, at most `maxMergeSources`, target not a source.
    static func validateMergeIds(from fromIds: [String], to toId: String) throws {
        guard fromIds.count <= maxMergeSources else {
            throw YNABMCPError.invalidParameter("from_payee_ids", detail: "merge at most \(maxMergeSources) payees per call")
        }
        guard Set(fromIds).count == fromIds.count else {
            throw YNABMCPError.invalidParameter("from_payee_ids", detail: "contains duplicates")
        }
        guard !fromIds.contains(toId) else {
            throw YNABMCPError.invalidParameter("from_payee_ids", detail: "must not include to_payee_id")
        }
    }
}
