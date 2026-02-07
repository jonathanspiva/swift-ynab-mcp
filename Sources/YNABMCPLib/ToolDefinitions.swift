import Foundation
import MCP

// MARK: - Tool Definitions

extension ToolHandlers {

    // MARK: - Annotations

    static let readOnly = Tool.Annotations(
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
    )

    static let writeAction = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
    )

    // MARK: - Read Tools

    public static let listBudgetsTool = Tool(
        name: "list_budgets",
        description: "List all YNAB budgets with their names, IDs, and currency format",
        inputSchema: .object(["type": .string("object")]),
        annotations: readOnly
    )

    public static let listAccountsTool = Tool(
        name: "list_accounts",
        description: "List all accounts in a budget with name, type, balance, and status",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID to list accounts for"),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    public static let listCategoriesTool = Tool(
        name: "list_categories",
        description: "List all categories grouped by category group, with IDs. Use category IDs when creating or updating transactions.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    public static let getBudgetSummaryTool = Tool(
        name: "get_budget_summary",
        description: "Get a budget overview including accounts and category groups with balances",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    public static let listRecentTransactionsTool = Tool(
        name: "list_recent_transactions",
        description: "List recent transactions with ID, date, payee, category, amount, and memo. Returns transaction IDs needed for update_transaction.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "account_id": .object([
                    "type": .string("string"),
                    "description": .string("Optional account ID to filter by"),
                ]),
                "days": .object([
                    "type": .string("integer"),
                    "description": .string("Number of days to look back (default: 30)"),
                ]),
                "category_name": .object([
                    "type": .string("string"),
                    "description": .string("Optional category name to filter by (e.g. 'Uncategorized'). Case-insensitive."),
                ]),
                "since_date": .object([
                    "type": .string("string"),
                    "description": .string("Start date in YYYY-MM-DD format. Overrides 'days' when provided."),
                ]),
                "until_date": .object([
                    "type": .string("string"),
                    "description": .string("End date in YYYY-MM-DD format. Client-side filter applied after fetching."),
                ]),
                "approved": .object([
                    "type": .string("boolean"),
                    "description": .string("Filter by approved status (true/false). Omit to include all."),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    public static let getMonthSummaryTool = Tool(
        name: "get_month_summary",
        description: "Get category breakdown for a specific month with budgeted, activity, and available amounts",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "month": .object([
                    "type": .string("string"),
                    "description": .string("The month in YYYY-MM-DD format (first day of month, e.g. 2025-01-01)"),
                ]),
            ]),
            "required": .array([.string("budget_id"), .string("month")]),
        ]),
        annotations: readOnly
    )

    public static let getTransactionTool = Tool(
        name: "get_transaction",
        description: "Get a single transaction with full details including account, payee, category, cleared/approved status, flag, and memo",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "transaction_id": .object([
                    "type": .string("string"),
                    "description": .string("The transaction ID"),
                ]),
            ]),
            "required": .array([.string("budget_id"), .string("transaction_id")]),
        ]),
        annotations: readOnly
    )

    public static let listPayeesTool = Tool(
        name: "list_payees",
        description: "List all payees with IDs for consistency review. Transfer payees are marked with (transfer) suffix.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    public static let getTransactionsByPayeeTool = Tool(
        name: "get_transactions_by_payee",
        description: "Get all transactions for a specific payee, with optional date range filtering",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "payee_id": .object([
                    "type": .string("string"),
                    "description": .string("The payee ID"),
                ]),
                "since_date": .object([
                    "type": .string("string"),
                    "description": .string("Start date in YYYY-MM-DD format (optional)"),
                ]),
                "until_date": .object([
                    "type": .string("string"),
                    "description": .string("End date in YYYY-MM-DD format (optional, client-side filter)"),
                ]),
            ]),
            "required": .array([.string("budget_id"), .string("payee_id")]),
        ]),
        annotations: readOnly
    )

    public static let getTransactionsByCategoryTool = Tool(
        name: "get_transactions_by_category",
        description: "Get all transactions for a specific category, with optional date range filtering",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "category_id": .object([
                    "type": .string("string"),
                    "description": .string("The category ID"),
                ]),
                "since_date": .object([
                    "type": .string("string"),
                    "description": .string("Start date in YYYY-MM-DD format (optional)"),
                ]),
                "until_date": .object([
                    "type": .string("string"),
                    "description": .string("End date in YYYY-MM-DD format (optional, client-side filter)"),
                ]),
            ]),
            "required": .array([.string("budget_id"), .string("category_id")]),
        ]),
        annotations: readOnly
    )

    public static let listScheduledTransactionsTool = Tool(
        name: "list_scheduled_transactions",
        description: "List all scheduled/recurring transactions with payee, amount, frequency, next date, account, and category",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
            ]),
            "required": .array([.string("budget_id")]),
        ]),
        annotations: readOnly
    )

    // MARK: - Write Tools

    public static let createTransactionTool = Tool(
        name: "create_transaction",
        description: "Create a new transaction in YNAB. Amount is in dollars (e.g. -50.00 for an expense, 100.00 for income)",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "account_id": .object([
                    "type": .string("string"),
                    "description": .string("The account ID to create the transaction in"),
                ]),
                "date": .object([
                    "type": .string("string"),
                    "description": .string("Transaction date in YYYY-MM-DD format"),
                ]),
                "amount": .object([
                    "type": .string("number"),
                    "description": .string("Amount in dollars (negative for expenses, positive for income)"),
                ]),
                "payee_name": .object([
                    "type": .string("string"),
                    "description": .string("Name of the payee"),
                ]),
                "category_id": .object([
                    "type": .string("string"),
                    "description": .string("Category ID for the transaction"),
                ]),
                "memo": .object([
                    "type": .string("string"),
                    "description": .string("Optional memo/note"),
                ]),
                "cleared": .object([
                    "type": .string("string"),
                    "description": .string("Cleared status: cleared, uncleared, or reconciled (default: uncleared)"),
                ]),
            ]),
            "required": .array([
                .string("budget_id"),
                .string("account_id"),
                .string("date"),
                .string("amount"),
            ]),
        ]),
        annotations: writeAction
    )

    public static let updateTransactionTool = Tool(
        name: "update_transaction",
        description: "Update an existing transaction in YNAB. Only provided fields will be changed. Amount is in dollars (e.g. -50.00 for an expense, 100.00 for income)",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "transaction_id": .object([
                    "type": .string("string"),
                    "description": .string("The ID of the transaction to update"),
                ]),
                "account_id": .object([
                    "type": .string("string"),
                    "description": .string("The account ID (only if moving the transaction)"),
                ]),
                "date": .object([
                    "type": .string("string"),
                    "description": .string("Transaction date in YYYY-MM-DD format"),
                ]),
                "amount": .object([
                    "type": .string("number"),
                    "description": .string("Amount in dollars (negative for expenses, positive for income)"),
                ]),
                "payee_name": .object([
                    "type": .string("string"),
                    "description": .string("Name of the payee"),
                ]),
                "category_id": .object([
                    "type": .string("string"),
                    "description": .string("Category ID for the transaction"),
                ]),
                "memo": .object([
                    "type": .string("string"),
                    "description": .string("Memo/note for the transaction"),
                ]),
                "cleared": .object([
                    "type": .string("string"),
                    "description": .string("Cleared status: cleared, uncleared, or reconciled"),
                ]),
                "approved": .object([
                    "type": .string("boolean"),
                    "description": .string("Whether the transaction is approved"),
                ]),
                "flag_color": .object([
                    "type": .string("string"),
                    "description": .string("Flag color: red, orange, yellow, green, blue, purple, or none to remove"),
                ]),
            ]),
            "required": .array([
                .string("budget_id"),
                .string("transaction_id"),
            ]),
        ]),
        annotations: writeAction
    )

    public static let bulkUpdateTransactionsTool = Tool(
        name: "bulk_update_transactions",
        description: "Update multiple transactions at once. Provide transaction IDs and the fields to change. All specified transactions will receive the same updates.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "transaction_ids": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Array of transaction IDs to update"),
                ]),
                "category_id": .object([
                    "type": .string("string"),
                    "description": .string("Category ID to set on all transactions"),
                ]),
                "payee_name": .object([
                    "type": .string("string"),
                    "description": .string("Payee name to set on all transactions"),
                ]),
                "approved": .object([
                    "type": .string("boolean"),
                    "description": .string("Approved status to set on all transactions"),
                ]),
                "flag_color": .object([
                    "type": .string("string"),
                    "description": .string("Flag color: red, orange, yellow, green, blue, purple, or none to remove"),
                ]),
                "cleared": .object([
                    "type": .string("string"),
                    "description": .string("Cleared status: cleared, uncleared, or reconciled"),
                ]),
                "memo": .object([
                    "type": .string("string"),
                    "description": .string("Memo to set on all transactions"),
                ]),
            ]),
            "required": .array([
                .string("budget_id"),
                .string("transaction_ids"),
            ]),
        ]),
        annotations: writeAction
    )

    public static let renamePayeeTool = Tool(
        name: "rename_payee",
        description: "Rename a payee by ID. Use list_payees to find payee IDs.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "payee_id": .object([
                    "type": .string("string"),
                    "description": .string("The payee ID to rename"),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("The new name for the payee (max 500 characters)"),
                ]),
            ]),
            "required": .array([
                .string("budget_id"),
                .string("payee_id"),
                .string("name"),
            ]),
        ]),
        annotations: writeAction
    )

    public static let updateCategoryBudgetTool = Tool(
        name: "update_category_budget",
        description: "Set the budgeted amount for a category in a specific month. Amount is in dollars.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "budget_id": .object([
                    "type": .string("string"),
                    "description": .string("The budget ID"),
                ]),
                "month": .object([
                    "type": .string("string"),
                    "description": .string("The month in YYYY-MM-DD format (first day of month, e.g. 2025-01-01) or 'current'"),
                ]),
                "category_id": .object([
                    "type": .string("string"),
                    "description": .string("The category ID"),
                ]),
                "amount": .object([
                    "type": .string("number"),
                    "description": .string("Budgeted amount in dollars (e.g. 500.00)"),
                ]),
            ]),
            "required": .array([
                .string("budget_id"),
                .string("month"),
                .string("category_id"),
                .string("amount"),
            ]),
        ]),
        annotations: writeAction
    )
}
