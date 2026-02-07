import Foundation
import SwiftYNAB

public actor YNABClient {
    private let ynab: YNAB
    private let rateLimiter: RateLimiter

    public init(accessToken: String, rateLimiter: RateLimiter) {
        self.ynab = YNAB(accessToken: accessToken)
        self.rateLimiter = rateLimiter
    }

    private func checkRate() async throws {
        let allowed = await rateLimiter.allowRequest()
        guard allowed else {
            let remaining = await rateLimiter.remaining
            throw YNABMCPError.rateLimited(remaining: remaining)
        }
    }

    // MARK: - Budgets

    public func listBudgets() async throws -> [BudgetSummary] {
        try await checkRate()
        return try await ynab.budgets.budgets(includeAccounts: false)
    }

    // MARK: - Accounts

    public func listAccounts(budgetId: String) async throws -> [Account] {
        try await checkRate()
        let result = try await ynab.accounts.accounts(
            budgetId: budgetId,
            lastKnowledgeOfServer: nil
        )
        return result.0
    }

    // MARK: - Budget Summary (full detail)

    public func getBudgetDetail(budgetId: String) async throws -> BudgetDetail {
        try await checkRate()
        let result = try await ynab.budgets.budget(budgetId: budgetId)
        return result.0
    }

    // MARK: - Categories

    public func listCategories(budgetId: String) async throws -> [CategoryGroupWithCategories] {
        try await checkRate()
        let result = try await ynab.categories.categories(
            budgetId: budgetId,
            lastKnowledgeOfServer: nil
        )
        return result.0
    }

    // MARK: - Transactions

    public func listTransactions(
        budgetId: String,
        accountId: String?,
        sinceDate: Date?
    ) async throws -> [TransactionDetail] {
        try await checkRate()
        if let accountId {
            let result = try await ynab.transactions.transactions(
                budgetId: budgetId,
                accountId: accountId,
                sinceDate: sinceDate,
                type: nil,
                lastKnowledgeOfServer: nil
            )
            return result.0
        } else {
            let result = try await ynab.transactions.transactions(
                budgetId: budgetId,
                sinceDate: sinceDate,
                type: nil,
                lastKnowledgeOfServer: nil
            )
            return result.0
        }
    }

    public func createTransaction(
        budgetId: String,
        accountId: String,
        date: String,
        amount: Int,
        payeeName: String?,
        categoryId: String?,
        memo: String?,
        cleared: ClearedStatus?
    ) async throws -> TransactionDetail {
        try await checkRate()
        let transaction = SaveTransactionWithIdOrImportId(
            id: nil,
            importId: nil,
            accountId: accountId,
            date: date,
            amount: Int64(amount),
            payeeId: nil,
            payeeName: payeeName,
            categoryId: categoryId,
            memo: memo,
            cleared: cleared ?? .uncleared,
            approved: true,
            flagColor: nil,
            subtransactions: nil
        )
        let result = try await ynab.transactions.createTransaction(
            budgetId: budgetId,
            transaction: transaction
        )
        return result.0
    }

    public func updateTransaction(
        budgetId: String,
        transactionId: String,
        accountId: String?,
        date: String?,
        amount: Int?,
        payeeName: String?,
        categoryId: String?,
        memo: String?,
        cleared: ClearedStatus?,
        approved: Bool? = nil,
        flagColor: FlagColor? = nil
    ) async throws -> TransactionDetail {
        try await checkRate()
        let transaction = SaveTransactionWithIdOrImportId(
            id: transactionId,
            importId: nil,
            accountId: accountId,
            date: date,
            amount: amount.map { Int64($0) },
            payeeId: nil,
            payeeName: payeeName,
            categoryId: categoryId,
            memo: memo,
            cleared: cleared,
            approved: approved,
            flagColor: flagColor,
            subtransactions: nil
        )
        return try await ynab.transactions.updateTransaction(
            budgetId: budgetId,
            transactionId: transactionId,
            transaction: transaction
        )
    }

    // MARK: - Single Transaction

    public func getTransaction(
        budgetId: String,
        transactionId: String
    ) async throws -> TransactionDetail {
        try await checkRate()
        let result = try await ynab.transactions.transaction(
            budgetId: budgetId,
            transactionId: transactionId
        )
        return result.0
    }

    // MARK: - Bulk Update

    public func bulkUpdateTransactions(
        budgetId: String,
        transactions: [SaveTransactionWithIdOrImportId]
    ) async throws -> [TransactionDetail] {
        try await checkRate()
        let result = try await ynab.transactions.updateTransactions(
            budgetId: budgetId,
            transactions: transactions
        )
        return result.0
    }

    // MARK: - Payees

    public func listPayees(budgetId: String) async throws -> [Payee] {
        try await checkRate()
        return try await ynab.payees.payees(
            budgetId: budgetId,
            lastKnowledgeOfServer: nil
        )
    }

    public func renamePayee(
        budgetId: String,
        payeeId: String,
        name: String
    ) async throws -> Payee {
        try await checkRate()
        let savePayee = SavePayee(name: name)
        let result = try await ynab.payees.updatePayee(
            budgetId: budgetId,
            payeeId: payeeId,
            payee: savePayee
        )
        return result.0
    }

    // MARK: - Transactions by Payee/Category

    public func transactionsByPayee(
        budgetId: String,
        payeeId: String,
        sinceDate: Date?
    ) async throws -> [HybridTransaction] {
        try await checkRate()
        let result = try await ynab.transactions.transactions(
            budgetId: budgetId,
            payeeId: payeeId,
            sinceDate: sinceDate,
            type: nil,
            lastKnowledgeOfServer: nil
        )
        return result.0
    }

    public func transactionsByCategory(
        budgetId: String,
        categoryId: String,
        sinceDate: Date?
    ) async throws -> [HybridTransaction] {
        try await checkRate()
        let result = try await ynab.transactions.transactions(
            budgetId: budgetId,
            categoryId: categoryId,
            sinceDate: sinceDate,
            type: nil,
            lastKnowledgeOfServer: nil
        )
        return result.0
    }

    // MARK: - Scheduled Transactions

    public func listScheduledTransactions(
        budgetId: String
    ) async throws -> [ScheduledTransactionDetail] {
        try await checkRate()
        let result = try await ynab.scheduledTransactions.scheduledTransactions(
            budgetId: budgetId,
            lastKnowledgeOfServer: nil
        )
        return result.0
    }

    // MARK: - Category Budget

    public func updateCategoryBudget(
        budgetId: String,
        month: String,
        categoryId: String,
        budgeted: Int
    ) async throws -> SwiftYNAB.Category {
        try await checkRate()
        return try await ynab.categories.updateCategory(
            budgetId: budgetId,
            month: month,
            categoryId: categoryId,
            budgeted: budgeted
        )
    }

    // MARK: - Months

    public func getMonth(budgetId: String, month: String) async throws -> MonthDetail {
        try await checkRate()
        return try await ynab.months.month(budgetId: budgetId, month: month)
    }
}

public enum YNABMCPError: Error, LocalizedError, CustomStringConvertible {
    case rateLimited(remaining: Int)
    case missingParameter(String)
    case invalidParameter(String, detail: String)

    public var description: String {
        switch self {
        case .rateLimited(let remaining):
            return "Rate limit exceeded. \(remaining) requests remaining in the current hour."
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameter(let name, let detail):
            return "Invalid parameter '\(name)': \(detail)"
        }
    }

    public var errorDescription: String? { description }
}
