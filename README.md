# YNAB MCP Server

[![CI](https://github.com/jonathanspiva/swift-ynab-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/jonathanspiva/swift-ynab-mcp/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26+-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-cc785c)](https://claude.ai/code)

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server for [YNAB](https://www.ynab.com) (You Need A Budget).

Gives AI assistants like Claude read and write access to your YNAB budgets, transactions, categories, and payees.

## Tools

### Read Tools (11)

| Tool | Description |
|------|-------------|
| `list_budgets` | List all budgets with names, IDs, and currency |
| `list_accounts` | List accounts in a budget with balances |
| `list_categories` | List category groups and categories with balances |
| `get_budget_summary` | Budget overview with accounts and category groups |
| `list_recent_transactions` | Recent transactions (filterable by account, date range, approval status) |
| `get_month_summary` | Category breakdown for a specific month |
| `get_transaction` | Full transaction details by ID |
| `list_payees` | List all payees in a budget |
| `get_transactions_by_payee` | Transaction history for a specific payee |
| `get_transactions_by_category` | Transaction history for a specific category |
| `list_scheduled_transactions` | List upcoming scheduled transactions |

### Write Tools (5)

| Tool | Description |
|------|-------------|
| `create_transaction` | Create a new transaction (amount in dollars) |
| `update_transaction` | Update an existing transaction (amount, payee, category, flag, approval) |
| `bulk_update_transactions` | Update multiple transactions at once |
| `rename_payee` | Rename a payee across all transactions |
| `update_category_budget` | Set the budgeted amount for a category in a given month |

## Requirements

- macOS 26+
- Swift 6.2+
- A [YNAB Personal Access Token](https://app.ynab.com/settings/developer)

## Build

```bash
swift build -c release
```

The binary will be at `.build/release/ynab-mcp`.

## Configure

Add to your Claude Code MCP config (`~/.claude.json` or project `.claude/settings.json`):

```json
{
  "mcpServers": {
    "ynab": {
      "command": "/path/to/ynab-mcp",
      "env": {
        "YNAB_TOKEN": "your-token-here"
      }
    }
  }
}
```

### 1Password integration

If you use 1Password, you can avoid storing the token in plaintext by using `op run`:

```json
{
  "mcpServers": {
    "ynab": {
      "command": "op",
      "args": ["run", "--no-masking", "--", "/path/to/ynab-mcp"],
      "env": {
        "YNAB_TOKEN": "op://Your Vault/YNAB Token/credential"
      }
    }
  }
}
```

## Rate Limiting

200 requests per hour (in-memory, resets on restart). This matches the YNAB API limit of 200 requests per hour per token.

## Dependencies

- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) - MCP protocol implementation for Swift
- [SwiftyNAB](https://github.com/andrebocchini/swiftynab) - YNAB API client for Swift

## Important: Back up your budget

This server includes write tools that modify your live YNAB data. **[Export your budget](https://support.ynab.com/en_us/how-to-export-plan-data-Sy_CouWA9) before using write tools for the first time.** In the YNAB web app, click your budget name in the top-left corner and choose "Export Budget."

## Notes

- Only tested with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It should work with any MCP client, but your mileage may vary.
- Write tools modify your actual YNAB data. Use with care.
- Transaction amounts are in dollars (e.g., `25.50`), not YNAB's native milliunits.
- Budget and category IDs can be discovered using the read tools (`list_budgets`, `list_categories`, etc.).

## License

MIT
