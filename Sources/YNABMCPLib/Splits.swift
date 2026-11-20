import Foundation
import MCP
import SwiftYNAB

/// One split line as passed by the caller, before transfer accounts are resolved to payee IDs.
public struct SplitLineInput: Equatable, Sendable {
    public var amount: Int
    public var categoryId: String?
    public var payeeName: String?
    public var memo: String?
    public var transferAccountId: String?
}

extension ToolHandlers {

    /// Parse the optional `subtransactions` argument. Returns nil when absent.
    public static func parseSplitLines(_ args: [String: Value], key: String = "subtransactions") throws -> [SplitLineInput]? {
        guard let raw = args[key], !raw.isNull else { return nil }
        guard let items = raw.arrayValue, items.count >= 2 else {
            throw YNABMCPError.invalidParameter(key, detail: "must be an array of at least 2 split lines")
        }
        return try items.enumerated().map { index, item in
            guard let line = item.objectValue else {
                throw YNABMCPError.invalidParameter(key, detail: "line \(index + 1) must be an object")
            }
            guard let amount = try optionalDouble(line, key: "amount") else {
                throw YNABMCPError.invalidParameter(key, detail: "line \(index + 1) needs an amount")
            }
            let input = SplitLineInput(
                amount: Formatters.milliunits(from: amount),
                categoryId: line["category_id"]?.stringValue,
                payeeName: line["payee_name"]?.stringValue,
                memo: line["memo"]?.stringValue,
                transferAccountId: line["transfer_account_id"]?.stringValue
            )
            if input.transferAccountId != nil && input.payeeName != nil {
                throw YNABMCPError.invalidParameter(
                    key, detail: "line \(index + 1) has both payee_name and transfer_account_id; pass one"
                )
            }
            return input
        }
    }

    /// YNAB rejects splits whose lines don't sum to the parent amount; catch it locally with a clearer message.
    public static func validateSplitTotal(_ lines: [SplitLineInput], total: Int) throws {
        let sum = lines.reduce(0) { $0 + $1.amount }
        guard sum == total else {
            throw YNABMCPError.invalidParameter(
                "subtransactions",
                detail: "lines add up to \(Formatters.money(sum)) but the transaction amount is \(Formatters.money(total))"
            )
        }
    }

    /// Reject `payee_name` together with `transfer_account_id`, since the transfer sets the payee.
    static func optionalTransferAccount(_ args: [String: Value]) throws -> String? {
        guard let id = args["transfer_account_id"]?.stringValue, !id.isEmpty else { return nil }
        if args["payee_name"]?.stringValue != nil {
            throw YNABMCPError.invalidParameter(
                "transfer_account_id", detail: "a transfer sets the payee itself; don't also pass payee_name"
            )
        }
        return id
    }

    /// Map account IDs to their transfer payee IDs with one list_accounts call (none if no IDs are given).
    static func transferPayeeIds(
        for accountIds: [String],
        planId: String,
        client: YNABClient
    ) async throws -> [String: String] {
        let wanted = Set(accountIds)
        guard !wanted.isEmpty else { return [:] }
        let accounts = try await client.listAccounts(planId: planId)
        var result: [String: String] = [:]
        for account in accounts where wanted.contains(account.id) && !account.deleted {
            if let payeeId = account.transferPayeeId {
                result[account.id] = payeeId
            }
        }
        if let missing = wanted.subtracting(result.keys).sorted().first {
            throw YNABMCPError.invalidParameter(
                "transfer_account_id", detail: "account `\(missing)` was not found (see list_accounts)"
            )
        }
        return result
    }

    static func saveSubtransactions(
        _ lines: [SplitLineInput],
        transferPayees: [String: String]
    ) -> [SaveSubTransaction] {
        lines.map { line in
            SaveSubTransaction(
                amount: line.amount,
                payeeId: line.transferAccountId.flatMap { transferPayees[$0] },
                payeeName: line.payeeName,
                categoryId: line.categoryId,
                memo: line.memo
            )
        }
    }
}
