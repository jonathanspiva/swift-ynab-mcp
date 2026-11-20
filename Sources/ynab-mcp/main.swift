import Foundation
import YNABMCPLib

guard let config = ServerConfig(environment: ProcessInfo.processInfo.environment) else {
    log("Error: YNAB_TOKEN environment variable is not set.")
    log("Get a personal access token at https://app.ynab.com/settings/developer")
    exit(1)
}

try await startServer(config: config)
