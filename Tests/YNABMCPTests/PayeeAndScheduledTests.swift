import Foundation
import Testing
import MCP
import SwiftYNAB
@testable import YNABMCPLib

@Suite("Bulk updates, payee merge, scheduled transactions")
struct PayeeAndScheduledTests {

    func makeClient() -> YNABClient {
        YNABClient(accessToken: "fake-token", rateLimiter: RateLimiter(maxRequests: 200, windowSeconds: 3600))
    }

    func errorText(_ name: String, _ args: [String: Value]) async -> String? {
        let result = await ToolHandlers.handleCall(name: name, arguments: args, client: makeClient())
        guard result.isError == true, case .text(let text, _, _) = result.content.first else { return nil }
        return text
    }

    // MARK: - Imported payee column

    @Test("importedPayee shows the raw bank string only when it adds information")
    func importedPayee() {
        #expect(Formatters.importedPayee("AplPay FRED MEYER PUYALLUP WA", payee: "Fred Meyer") == "AplPay FRED MEYER PUYALLUP WA")
        #expect(Formatters.importedPayee("Starbucks", payee: "Starbucks") == "")
        #expect(Formatters.importedPayee(nil, payee: "Starbucks") == "")
        #expect(Formatters.importedPayee("", payee: nil) == "")
    }

    @Test("Transaction tables include the Imported Payee column")
    func tableColumn() {
        let txn = ReportsTests.txn(amount: -1, payee: "Fred Meyer")
        let table = Formatters.formatTransactionDetailTable([txn], title: "")
        #expect(table.contains("| Memo | Imported Payee |"))
    }

    // MARK: - Bulk updates

    @Test("Shared fields apply to every transaction_id")
    func bulkShared() throws {
        let saves = try ToolHandlers.buildBulkUpdates([
            "transaction_ids": .array(["a", "b"]), "approved": true, "category_id": "c",
        ])
        #expect(saves.map(\.id) == ["a", "b"])
        #expect(saves.allSatisfy { $0.approved == true && $0.categoryId == "c" && $0.payeeName == nil })
    }

    @Test("Per-item updates give each transaction its own payee and memo, overriding shared fields")
    func bulkPerItem() throws {
        let saves = try ToolHandlers.buildBulkUpdates([
            "transaction_ids": .array(["a", "b"]),
            "approved": true,
            "memo": "shared",
            "updates": .array([
                .object(["transaction_id": "b", "payee_name": "Fred Meyer", "memo": "Puyallup, WA"]),
                .object(["transaction_id": "c", "payee_name": "Starbucks", "date": "2026-11-01"]),
            ]),
        ])
        #expect(saves.map(\.id) == ["a", "b", "c"])
        #expect(saves[0].memo == "shared" && saves[0].payeeName == nil && saves[0].approved == true)
        #expect(saves[1].payeeName == "Fred Meyer" && saves[1].memo == "Puyallup, WA" && saves[1].approved == true)
        #expect(saves[2].payeeName == "Starbucks" && saves[2].date == "2026-11-01" && saves[2].memo == "shared")
    }

    @Test("Bulk update rejects empty, duplicate, and change-less input")
    func bulkValidation() {
        #expect(throws: YNABMCPError.self) { try ToolHandlers.buildBulkUpdates([:]) }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.buildBulkUpdates(["transaction_ids": .array(["a"])]) }
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.buildBulkUpdates(["transaction_ids": .array(["a", "a"]), "approved": true])
        }
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.buildBulkUpdates(["updates": .array([
                .object(["transaction_id": "a", "memo": "x"]), .object(["transaction_id": "a", "memo": "y"]),
            ])])
        }
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.buildBulkUpdates(["updates": .array([.object(["memo": "no id"])])])
        }
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.buildBulkUpdates(["updates": .array([.object(["transaction_id": "a", "date": "11/01/2026"])])])
        }
    }

    @Test("A per-item payee replaces a shared payee rather than mixing payee_id and payee_name")
    func mergedPayee() {
        let shared = TransactionChanges(payeeId: "p1", memo: "m")
        let item = TransactionChanges(payeeName: "New")
        let merged = item.merged(over: shared)
        #expect(merged.payeeId == nil)
        #expect(merged.payeeName == "New")
        #expect(merged.memo == "m")
        #expect(TransactionChanges().merged(over: shared) == shared)
    }

    // MARK: - Payee merge

    static func hybrid(
        id: String,
        date: String = "2026-11-01",
        parent: String? = nil,
        deleted: Bool = false
    ) -> HybridTransaction {
        HybridTransaction(
            type: parent == nil ? "transaction" : "subtransaction", parentTransactionId: parent, id: id,
            date: date, amount: -1000, amountFormatted: nil, amountCurrency: nil, memo: nil,
            cleared: .cleared, approved: true, flagColor: nil, flagName: nil,
            accountId: "acct", accountName: "Checking", payeeId: "p", payeeName: "Payee",
            categoryId: nil, categoryName: nil, transferAccountId: nil, transferTransactionId: nil,
            matchedTransactionId: nil, importId: nil, importPayeeName: nil, importPayeeNameOriginal: nil,
            debtTransactionType: nil, deleted: deleted
        )
    }

    @Test("Merge plan moves whole transactions once, oldest first, and sets split lines aside")
    func mergePlan() {
        let plan = PayeeMergePlan([
            Self.hybrid(id: "b", date: "2026-10-02"),
            Self.hybrid(id: "a", date: "2026-10-01"),
            Self.hybrid(id: "a", date: "2026-10-01"),
            Self.hybrid(id: "s1", parent: "parent"),
            Self.hybrid(id: "gone", deleted: true),
        ])
        #expect(plan.movable.map(\.id) == ["a", "b"])
        #expect(plan.splitLines.map(\.id) == ["s1"])
    }

    @Test("Merge rejects duplicates, too many sources, and merging a payee into itself")
    func mergeValidation() async throws {
        try ToolHandlers.validateMergeIds(from: ["a", "b"], to: "c")
        #expect(throws: YNABMCPError.self) { try ToolHandlers.validateMergeIds(from: ["a", "a"], to: "c") }
        #expect(throws: YNABMCPError.self) { try ToolHandlers.validateMergeIds(from: ["a", "c"], to: "c") }
        #expect(throws: YNABMCPError.self) {
            try ToolHandlers.validateMergeIds(from: (0...10).map(String.init), to: "x")
        }
        let text = await errorText("merge_payees", ["from_payee_ids": .array(["c"]), "to_payee_id": "c"])
        #expect(text?.contains("to_payee_id") == true)
    }

    // MARK: - Scheduled transactions

    static func scheduled(subtransactions: [ScheduledSubTransaction] = []) -> ScheduledTransactionDetail {
        ScheduledTransactionDetail(
            id: "s", dateFirst: "2026-01-29", dateNext: "2026-11-29", frequency: .monthly,
            amount: -50_680, amountFormatted: nil, amountCurrency: nil, memo: "Life premium",
            flagColor: .blue, flagName: nil, accountId: "checking", accountName: "Checking",
            payeeId: "amfam", payeeName: "American Family", categoryId: "insurance",
            categoryName: "Insurance", transferAccountId: nil, deleted: false,
            subtransactions: subtransactions
        )
    }

    @Test("Scheduled edits keep every field that isn't changed")
    func scheduledKeepsFields() {
        let save = ScheduledChanges(amount: -55_000).applied(to: Self.scheduled())
        #expect(save == SaveScheduledTransaction(
            accountId: "checking", date: "2026-11-29", amount: -55_000, payeeId: "amfam", payeeName: nil,
            categoryId: "insurance", memo: "Life premium", flagColor: .blue, frequency: .monthly
        ))
    }

    @Test("A new scheduled payee replaces the old payee ID")
    func scheduledNewPayee() {
        let byName = ScheduledChanges(payeeName: "AmFam Life").applied(to: Self.scheduled())
        #expect(byName.payeeId == nil && byName.payeeName == "AmFam Life")
        let transfer = ScheduledChanges(payeeId: "transfer-payee").applied(to: Self.scheduled())
        #expect(transfer.payeeId == "transfer-payee" && transfer.payeeName == nil)
    }

    @Test("parseFrequency accepts YNAB's names and rejects others")
    func frequency() throws {
        #expect(try ToolHandlers.parseFrequency("everyOtherWeek") == .everyOtherWeek)
        #expect(try ToolHandlers.parseFrequency(nil) == nil)
        #expect(throws: YNABMCPError.self) { try ToolHandlers.parseFrequency("fortnightly") }
        #expect(ToolHandlers.frequencies.count == 13)
        #expect(ToolHandlers.frequencies.allSatisfy { ScheduledTransactionFrequency(rawValue: $0) != nil })
    }

    @Test("Scheduled tools validate input before calling YNAB")
    func scheduledValidation() async {
        let badFrequency = await errorText("create_scheduled_transaction", [
            "account_id": "a", "date": "2026-12-01", "amount": .double(-50), "frequency": "fortnightly",
        ])
        #expect(badFrequency?.contains("frequency") == true)
        let missing = await errorText("create_scheduled_transaction", ["account_id": "a", "date": "2026-12-01", "amount": .double(-50)])
        #expect(missing?.contains("frequency") == true)
        let noChanges = await errorText("update_scheduled_transaction", ["scheduled_transaction_id": "s"])
        #expect(noChanges?.contains("at least one field") == true)
    }
}
