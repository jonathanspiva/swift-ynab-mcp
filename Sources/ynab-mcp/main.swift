import Foundation
import YNABMCPLib

guard let token = ProcessInfo.processInfo.environment["YNAB_TOKEN"], !token.isEmpty else {
    log("Error: YNAB_TOKEN environment variable is not set.")
    log("Get your personal access token at: https://app.ynab.com/settings/developer")
    exit(1)
}

let rateLimiter = RateLimiter()
let client = YNABClient(accessToken: token, rateLimiter: rateLimiter)

try await startServer(client: client)
