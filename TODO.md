## Now
- [ ] Merge duplicate payee entries in YNAB (API renames the payee but doesn't merge the underlying IDs, so YNAB may still show duplicates until manually merged in the app)

## Later
- [ ] Add `payee_id` parameter to `update_transaction` and `create_transaction` (enables creating proper transfers between accounts, e.g. linking a withdrawal to a tracking account)
- [ ] Add filters to `list_recent_transactions`: `exclude_transfers`, `exclude_reconciliation`, `on_budget_only` (reduces noise when triaging uncategorized transactions)
- [ ] Add `sort_by` parameter to `list_recent_transactions` (e.g. sort by amount to find largest uncategorized transactions)
- [ ] Add `delete_transaction` tool (soft delete via YNAB API)
- [ ] Add `create_scheduled_transaction` tool
- [ ] Add `get_account` tool for single account details
- [ ] Add payee auto-rename rules (e.g., import payee matching patterns)
- [ ] Add spending summary tool (aggregate by payee or category over date range)
- [ ] Improve error messages with actionable hints (e.g., "use list_categories to find category IDs")

## Never
- [ ] Bulk delete transactions (too destructive for an MCP tool)

## Done
