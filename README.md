# YNAB MCP Server

[![CI](https://github.com/jonathanspiva/swift-ynab-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/jonathanspiva/swift-ynab-mcp/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26+-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-cc785c)](https://claude.ai/code)

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server for [YNAB](https://www.ynab.com) (You Need A Budget).

Gives AI assistants like Claude read and write access to your YNAB plans, transactions, categories, and payees.

## Tools

Every tool takes an optional `plan_id`. When it's omitted the server uses your last-used plan (or `YNAB_PLAN_ID`, if set), so most conversations never need to look up an ID.

### Read Tools (13)

| Tool | Description |
|------|-------------|
| `list_plans` | List all plans with names, IDs, and currency |
| `get_plan_summary` | Open account balances plus current-month category amounts |
| `list_accounts` | Accounts with balances, type, and reconciliation status |
| `list_categories` | Category groups and categories with IDs and amounts |
| `get_month_summary` | Income, assigned, activity, Ready to Assign, and per-category breakdown for a month |
| `list_transactions` | Transactions by date range, account, category, or `unapproved`/`uncategorized` |
| `get_transaction` | Full transaction details, including split lines |
| `get_transactions_by_payee` | Transaction history for a payee |
| `get_transactions_by_category` | Transaction history for a category |
| `list_payees` | Payees with IDs, optionally filtered by name |
| `list_scheduled_transactions` | Upcoming scheduled transactions |
| `spending_report` | Spending over a date range by category, category group, payee, or month (splits broken out, transfers excluded, income shown separately) |
| `monthly_trends` | Month-by-month income, assigned, activity, Ready to Assign, and age of money, with averages |

### Write Tools (8)

| Tool | Description |
|------|-------------|
| `create_transaction` | Create a transaction, transfer (`transfer_account_id`), or split (`subtransactions`) |
| `update_transaction` | Change any fields of one transaction, convert it to a transfer, or split it |
| `bulk_update_transactions` | Apply the same changes to many transactions in one request |
| `delete_transaction` | Permanently delete a transaction (marked destructive) |
| `rename_payee` | Rename a payee everywhere it is used |
| `set_category_assigned` | Set a category's assigned amount for a month |
| `create_account` | Create an unlinked on-budget or tracking account |
| `reconcile_account` | Reconcile to a statement balance: add a balance adjustment if needed and lock cleared transactions (`dry_run` to preview) |

YNAB doesn't allow editing the lines of a transaction that is already split. `update_transaction` can split an unsplit transaction, but to change an existing split, delete and recreate it.

Write tools are hidden entirely when `YNAB_READ_ONLY` is set.

## Requirements

- macOS 26+ (developed on macOS 27 with Swift 6.4)
- Swift 6.2+
- A [YNAB Personal Access Token](https://app.ynab.com/settings/developer)

## Build

```bash
swift build -c release
```

The binary will be at `.build/release/ynab-mcp`.

## Configure

| Variable | Required | Description |
|----------|----------|-------------|
| `YNAB_TOKEN` | yes | Your YNAB personal access token |
| `YNAB_PLAN_ID` | no | Plan used when a tool call omits `plan_id` (default: `last-used`; `default` also works) |
| `YNAB_READ_ONLY` | no | Set to `1` to expose only the read tools |

Add it to Claude Code for all projects:

```bash
claude mcp add ynab --scope user -e YNAB_TOKEN=your-token-here -- /path/to/ynab-mcp
```

Or check a `.mcp.json` into a project:

```json
{
  "mcpServers": {
    "ynab": {
      "command": "/path/to/ynab-mcp",
      "env": {
        "YNAB_TOKEN": "${YNAB_TOKEN}",
        "YNAB_READ_ONLY": "1"
      }
    }
  }
}
```

### 1Password integration

If you use 1Password, you can avoid storing the token in plaintext by using `op run`:

```bash
claude mcp add ynab --scope user \
  -e "YNAB_TOKEN=op://Your Vault/YNAB Token/credential" \
  -- op run --no-masking -- /path/to/ynab-mcp
```

**Limitation:** `op` requires an active biometric session. Claude Code spawns MCP servers non-interactively, so `op` can't prompt for authentication. If your session has expired, the MCP server will silently fail to connect, and `/mcp` reconnect won't help either.

To fix this, run any `op` command in a terminal first to establish a session, then restart Claude Code:

```bash
op read "op://Your Vault/YNAB Token/credential" > /dev/null
```

This is a [known limitation](https://github.com/anthropics/claude-code/issues/23642) of how Claude Code launches subprocesses.

### Local development

Put a 1Password reference (not the token itself) in a gitignored `.env`:

```bash
YNAB_TOKEN=op://<vault>/<item>/credential
```

Then run anything that needs the token through `op run`, for example a read-only session:

```bash
YNAB_READ_ONLY=1 op run --env-file .env -- .build/release/ynab-mcp
```

## Rate Limiting

YNAB allows 200 requests per hour per token. The server tracks this in memory (it resets on restart) and refuses calls past the limit with a clear message instead of letting YNAB return errors. Most tool calls cost one request. The exceptions: `get_plan_summary` costs two; `spending_report` two or three; `create_transaction` and `update_transaction` one more when they involve a transfer or (for an update) a split without a new amount; `reconcile_account` up to five.

## Dependencies

- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) - MCP protocol implementation for Swift
- [SwiftyNAB](https://github.com/andrebocchini/swiftynab) - YNAB API client for Swift

## Important: Back up your budget

This server includes write tools that modify your live YNAB data. **[Export your budget](https://support.ynab.com/en_us/how-to-export-plan-data-Sy_CouWA9) before using write tools for the first time.** In the YNAB web app, click your budget name in the top-left corner and choose "Export Budget."

## Notes

- Only tested with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It should work with any MCP client, but your mileage may vary.
- Write tools modify your actual YNAB data. Use with care.
- Amounts are in your plan's currency units (e.g. `-25.50`), not YNAB's native milliunits. Output uses YNAB's own currency formatting.
- YNAB renamed "budgets" to "plans" in 2026; this server follows the new API naming.
- IDs can be discovered with the read tools (`list_accounts`, `list_categories`, `list_payees`).

## Inspiration

Feature ideas and conventions borrowed from two other community YNAB servers worth a look:

- [calebl/ynab-mcp-server](https://github.com/calebl/ynab-mcp-server) (TypeScript): read-only mode, spending and cash-flow reports, remote deployment
- [oliverames/ynab-mcp-server](https://github.com/oliverames/ynab-mcp-server) (JavaScript): near-complete API coverage, write previews and undo, transfer and split handling

YNAB does not publish an official MCP server.

## License

MIT
