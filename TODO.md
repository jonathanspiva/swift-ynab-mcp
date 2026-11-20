## Now
- [ ] Merge duplicate payee entries in YNAB (API renames the payee but doesn't merge the underlying IDs, so YNAB may still show duplicates until manually merged in the app)
- [ ] Verify v2.0.0 against the live API (all read tools, then one write round-trip on a test transaction)

## Later
- [ ] Add `payee_id` parameter to `update_transaction` and `create_transaction` (enables creating proper transfers between accounts, e.g. linking a withdrawal to a tracking account)
- [ ] Transfers by account: `transfer_to_account_id` that resolves the account's transfer payee
- [ ] Split transactions: create, read, and update subtransactions
- [ ] Add filters to `list_transactions`: `exclude_transfers`, `exclude_reconciliation`, `on_budget_only` (reduces noise when triaging uncategorized transactions)
- [ ] Add `sort_by` parameter to `list_transactions` (e.g. sort by amount to find largest uncategorized transactions)
- [ ] Add `delete_transaction` tool (soft delete via YNAB API)
- [ ] Scheduled transaction writes (create, update, delete)
- [ ] Add `get_account` tool for single account details
- [ ] Move money between categories (`move_category_assigned`: one call, two category updates)
- [ ] Spending summary tool (aggregate by payee or category over date range)
- [ ] Reports: cash flow, recurring charge detection, scheduled balance forecast
- [ ] `list_months` for month-over-month trends
- [ ] Delta sync / short-lived cache via `server_knowledge` to save rate-limit budget
- [ ] Add payee auto-rename rules (e.g., import payee matching patterns)
- [ ] Raise manifest floor to Swift 6.4 / macOS 27 once GitHub ships a macOS 27 runner

## Never
- [ ] Bulk delete transactions (too destructive for an MCP tool)

## Done
- [x] Compile on Swift 6.4 (swift-sdk 0.12.1, SwiftyNAB 5.1)
- [x] Adopt YNAB "plans" API naming; `plan_id` optional with `last-used` default and `YNAB_PLAN_ID`
- [x] `YNAB_READ_ONLY` mode
- [x] Server instructions, tool titles, accurate annotations, strict schemas
- [x] Reject invalid enum, date, and month values instead of silently ignoring them
- [x] Improve error messages with actionable hints (e.g., "use list_categories to find category IDs")
- [x] Use YNAB's currency-formatted amounts instead of hard-coded USD
- [x] Server-side `until_date`, `type` filter, and `limit` on transaction lists
