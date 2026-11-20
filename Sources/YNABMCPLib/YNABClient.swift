import Foundation
import SwiftYNAB

/// Thin, rate-limited wrapper around SwiftYNAB. Every method costs one YNAB API request.
public actor YNABClient {
    private let ynab: YNAB
    private let rateLimiter: RateLimiter

    /// Plan used when a tool call omits `plan_id`. YNAB accepts "last-used" and "default" as aliases.
    public nonisolated let defaultPlanId: String

    public init(accessToken: String, rateLimiter: RateLimiter, defaultPlanId: String = "last-used") {
        self.ynab = YNAB(accessToken: accessToken)
        self.rateLimiter = rateLimiter
        self.defaultPlanId = defaultPlanId
    }

    private func checkRate() async throws {
        guard await rateLimiter.allowRequest() else {
            throw YNABMCPError.rateLimited(remaining: await rateLimiter.remaining)
        }
    }

    // MARK: - Plans

    public func listPlans() async throws -> [PlanSummary] {
        try await checkRate()
        return try await ynab.plans.plans(includeAccounts: false)
    }

    // MARK: - Accounts

    public func listAccounts(planId: String) async throws -> [Account] {
        try await checkRate()
        return try await ynab.accounts.accounts(planId: planId, lastKnowledgeOfServer: nil).accounts
    }

    public func getAccount(planId: String, accountId: String) async throws -> Account {
        try await checkRate()
        return try await ynab.accounts.account(planId: planId, accountId: accountId)
    }

    public func createAccount(
        planId: String,
        name: String,
        type: SaveAccountType,
        balance: Int
    ) async throws -> Account {
        try await checkRate()
        return try await ynab.accounts.newPlanAccount(planId: planId, name: name, type: type, balance: balance)
    }

    // MARK: - Categories

    public func listCategories(planId: String) async throws -> [CategoryGroupWithCategories] {
        try await checkRate()
        return try await ynab.categories.categories(planId: planId, lastKnowledgeOfServer: nil).categoryGroups
    }

    public func updateCategoryAssigned(
        planId: String,
        month: String,
        categoryId: String,
        budgeted: Int
    ) async throws -> SwiftYNAB.Category {
        try await checkRate()
        return try await ynab.categories.updateCategory(
            planId: planId,
            month: month,
            categoryId: categoryId,
            budgeted: budgeted
        )
    }

    // MARK: - Months

    public func getMonth(planId: String, month: String) async throws -> MonthDetail {
        try await checkRate()
        return try await ynab.months.month(planId: planId, month: month)
    }

    public func listMonths(planId: String) async throws -> [MonthSummary] {
        try await checkRate()
        return try await ynab.months.months(planId: planId, lastKnowledgeOfServer: nil).months
    }

    // MARK: - Transactions

    public func listTransactions(
        planId: String,
        accountId: String?,
        query: TransactionQuery
    ) async throws -> [TransactionDetail] {
        try await checkRate()
        if let accountId {
            return try await ynab.transactions.transactions(
                planId: planId, accountId: accountId, query: query
            ).transactions
        }
        return try await ynab.transactions.transactions(planId: planId, query: query).transactions
    }

    public func transactionsByPayee(
        planId: String,
        payeeId: String,
        query: TransactionQuery
    ) async throws -> [HybridTransaction] {
        try await checkRate()
        return try await ynab.transactions.transactions(
            planId: planId, payeeId: payeeId, query: query
        ).transactions
    }

    public func transactionsByCategory(
        planId: String,
        categoryId: String,
        query: TransactionQuery
    ) async throws -> [HybridTransaction] {
        try await checkRate()
        return try await ynab.transactions.transactions(
            planId: planId, categoryId: categoryId, query: query
        ).transactions
    }

    public func getTransaction(planId: String, transactionId: String) async throws -> TransactionDetail {
        try await checkRate()
        return try await ynab.transactions.transaction(planId: planId, transactionId: transactionId).transaction
    }

    public func createTransaction(planId: String, transaction: NewTransaction) async throws -> TransactionDetail {
        try await checkRate()
        let response = try await ynab.transactions.createTransaction(planId: planId, transaction: transaction)
        guard let created = response.transaction else {
            throw YNABMCPError.unexpectedResponse("YNAB did not return the created transaction")
        }
        return created
    }

    public func updateTransaction(
        planId: String,
        transactionId: String,
        transaction: ExistingTransaction
    ) async throws -> TransactionDetail {
        try await checkRate()
        return try await ynab.transactions.updateTransaction(
            planId: planId, transactionId: transactionId, transaction: transaction
        ).transaction
    }

    public func updateTransactions(
        planId: String,
        transactions: [SaveTransactionWithIdOrImportId]
    ) async throws -> [TransactionDetail] {
        try await checkRate()
        return try await ynab.transactions.updateTransactions(
            planId: planId, transactions: transactions
        ).transactions ?? []
    }

    public func deleteTransaction(planId: String, transactionId: String) async throws -> TransactionDetail? {
        try await checkRate()
        return try await ynab.transactions.deleteTransaction(
            planId: planId, transactionId: transactionId
        ).transaction
    }

    // MARK: - Scheduled Transactions

    public func listScheduledTransactions(planId: String) async throws -> [ScheduledTransactionDetail] {
        try await checkRate()
        return try await ynab.scheduledTransactions.scheduledTransactions(
            planId: planId, lastKnowledgeOfServer: nil
        ).scheduledTransactions
    }

    public func getScheduledTransaction(planId: String, id: String) async throws -> ScheduledTransactionDetail {
        try await checkRate()
        return try await ynab.scheduledTransactions.scheduledTransaction(planId: planId, transactionId: id)
    }

    public func createScheduledTransaction(
        planId: String,
        transaction: SaveScheduledTransaction
    ) async throws -> ScheduledTransactionDetail {
        try await checkRate()
        return try await ynab.scheduledTransactions.createScheduledTransaction(planId: planId, transaction: transaction)
    }

    public func updateScheduledTransaction(
        planId: String,
        id: String,
        transaction: SaveScheduledTransaction
    ) async throws -> ScheduledTransactionDetail {
        try await checkRate()
        return try await ynab.scheduledTransactions.updateScheduledTransaction(
            planId: planId, transactionId: id, transaction: transaction
        )
    }

    public func deleteScheduledTransaction(planId: String, id: String) async throws -> ScheduledTransactionDetail {
        try await checkRate()
        return try await ynab.scheduledTransactions.deleteScheduledTransaction(planId: planId, transactionId: id)
    }

    // MARK: - Payees

    public func listPayees(planId: String) async throws -> [Payee] {
        try await checkRate()
        return try await ynab.payees.payees(planId: planId, lastKnowledgeOfServer: nil).payees
    }

    public func renamePayee(planId: String, payeeId: String, name: String) async throws -> Payee {
        try await checkRate()
        return try await ynab.payees.updatePayee(
            planId: planId, payeeId: payeeId, payee: SavePayee(name: name)
        ).payee
    }
}
