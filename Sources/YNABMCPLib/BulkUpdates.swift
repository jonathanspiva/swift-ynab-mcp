import Foundation
import MCP
import SwiftYNAB

/// Field changes for one transaction in a bulk update. nil means "leave as is".
public struct TransactionChanges: Equatable, Sendable {
    public var payeeId: String?
    public var payeeName: String?
    public var categoryId: String?
    public var memo: String?
    public var date: String?
    public var cleared: ClearedStatus?
    public var approved: Bool?
    public var flagColor: FlagColor?

    public init(
        payeeId: String? = nil,
        payeeName: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        date: String? = nil,
        cleared: ClearedStatus? = nil,
        approved: Bool? = nil,
        flagColor: FlagColor? = nil
    ) {
        self.payeeId = payeeId
        self.payeeName = payeeName
        self.categoryId = categoryId
        self.memo = memo
        self.date = date
        self.cleared = cleared
        self.approved = approved
        self.flagColor = flagColor
    }

    public var isEmpty: Bool { self == TransactionChanges() }

    /// Fields set here win; unset fields fall back to `base`. Setting either payee field
    /// replaces both, so a per-item payee_name isn't combined with a shared payee_id.
    public func merged(over base: TransactionChanges) -> TransactionChanges {
        let hasPayee = payeeId != nil || payeeName != nil
        return TransactionChanges(
            payeeId: hasPayee ? payeeId : base.payeeId,
            payeeName: hasPayee ? payeeName : base.payeeName,
            categoryId: categoryId ?? base.categoryId,
            memo: memo ?? base.memo,
            date: date ?? base.date,
            cleared: cleared ?? base.cleared,
            approved: approved ?? base.approved,
            flagColor: flagColor ?? base.flagColor
        )
    }

    func save(id: String) -> SaveTransactionWithIdOrImportId {
        SaveTransactionWithIdOrImportId(
            id: id,
            importId: nil,
            accountId: nil,
            date: date,
            amount: nil,
            payeeId: payeeId,
            payeeName: payeeName,
            categoryId: categoryId,
            memo: memo,
            cleared: cleared,
            approved: approved,
            flagColor: flagColor,
            subtransactions: nil
        )
    }
}

extension ToolHandlers {

    static let changeFieldNames = "payee_name, category_id, memo, date, cleared, approved, flag_color"

    /// Read the change fields shared by bulk_update_transactions and its per-item `updates`.
    static func parseChanges(_ args: [String: Value]) throws -> TransactionChanges {
        TransactionChanges(
            payeeName: args["payee_name"]?.stringValue,
            categoryId: args["category_id"]?.stringValue,
            memo: args["memo"]?.stringValue,
            date: args["date"] == nil ? nil : try requireDateString(args, key: "date"),
            cleared: try parseClearedStatus(args["cleared"]?.stringValue),
            approved: try optionalBool(args, key: "approved"),
            flagColor: try parseFlagColor(args["flag_color"]?.stringValue)
        )
    }

    /// Build the YNAB payload for bulk_update_transactions. Shared fields apply to every listed
    /// transaction; each entry in `updates` can override them for its own transaction.
    /// Order follows `transaction_ids`, then any IDs that appear only in `updates`.
    public static func buildBulkUpdates(_ args: [String: Value]) throws -> [SaveTransactionWithIdOrImportId] {
        let shared = try parseChanges(args)
        let sharedIds = args["transaction_ids"] == nil ? [] : try requireStringArray(args, key: "transaction_ids")

        var perItem: [String: TransactionChanges] = [:]
        var order = sharedIds
        if let raw = args["updates"], !raw.isNull {
            guard let items = raw.arrayValue, !items.isEmpty else {
                throw YNABMCPError.invalidParameter("updates", detail: "must be a non-empty array")
            }
            for (index, item) in items.enumerated() {
                guard let fields = item.objectValue,
                      let id = fields["transaction_id"]?.stringValue, !id.isEmpty else {
                    throw YNABMCPError.invalidParameter("updates", detail: "item \(index + 1) needs a transaction_id")
                }
                guard perItem[id] == nil else {
                    throw YNABMCPError.invalidParameter("updates", detail: "transaction `\(id)` is listed twice")
                }
                perItem[id] = try parseChanges(fields)
                if !sharedIds.contains(id) { order.append(id) }
            }
        }
        guard !order.isEmpty else {
            throw YNABMCPError.invalidParameter("bulk_update_transactions", detail: "pass transaction_ids, updates, or both")
        }
        guard Set(sharedIds).count == sharedIds.count else {
            throw YNABMCPError.invalidParameter("transaction_ids", detail: "contains duplicates")
        }

        return try order.map { id in
            let changes = (perItem[id] ?? TransactionChanges()).merged(over: shared)
            guard !changes.isEmpty else {
                throw YNABMCPError.invalidParameter(
                    "bulk_update_transactions", detail: "no changes for `\(id)`; set at least one of \(changeFieldNames)"
                )
            }
            return changes.save(id: id)
        }
    }
}
