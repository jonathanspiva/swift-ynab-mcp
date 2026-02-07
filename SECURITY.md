# Security

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it privately by emailing **jonathan.spiva@74bit.com**.

Please do not open a public issue for security vulnerabilities.

## Security Considerations

This MCP server has **read and write access** to your YNAB budget data. Before using it:

- **Back up your budget.** Export your data from YNAB first: open the [YNAB web app](https://app.ynab.com), click your budget name in the top-left corner, and choose "Export Budget." See [YNAB's export guide](https://support.ynab.com/en_us/how-to-export-plan-data-Sy_CouWA9) for details.
- **Protect your API token.** Never commit your YNAB Personal Access Token to source control. Use environment variables or a secret manager like 1Password.
- **Review write operations.** The write tools (`create_transaction`, `update_transaction`, `rename_payee`, etc.) modify your live YNAB data. Verify changes in the YNAB app after use.
