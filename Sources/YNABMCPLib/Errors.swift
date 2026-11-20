import Foundation
import SwiftYNAB

public enum YNABMCPError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case rateLimited(remaining: Int)
    case missingParameter(String)
    case invalidParameter(String, detail: String)
    case readOnlyMode(tool: String)
    case unexpectedResponse(String)

    public var description: String {
        switch self {
        case .rateLimited:
            return "Local rate limit reached (YNAB allows 200 requests per hour per token). Wait a few minutes and retry, or narrow the request."
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameter(let name, let detail):
            return "Invalid parameter '\(name)': \(detail)"
        case .readOnlyMode(let tool):
            return "'\(tool)' modifies YNAB data, but this server is running with YNAB_READ_ONLY enabled."
        case .unexpectedResponse(let detail):
            return "Unexpected response from YNAB: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}

public enum ErrorFormatter {
    /// Turn any thrown error into a message the model can act on.
    public static func message(for error: Error) -> String {
        switch error {
        case let error as YNABMCPError:
            return error.description
        case let error as SwiftYNABError:
            return message(for: error)
        default:
            return error.localizedDescription
        }
    }

    static func message(for error: SwiftYNABError) -> String {
        switch error {
        case .apiError(let detail):
            let base = "YNAB API error \(detail.id) (\(detail.name)): \(detail.detail)"
            guard let hint = hint(forErrorId: detail.id) else { return base }
            return "\(base)\nHint: \(hint)"
        case .httpError(let statusCode):
            let base = "YNAB returned HTTP \(statusCode)."
            guard let hint = hint(forErrorId: String(statusCode)) else { return base }
            return "\(base)\nHint: \(hint)"
        case .decodingFailure(let message):
            return "Could not decode the YNAB response: \(message)"
        case .encodingFailure(let message):
            return "Could not encode the request for YNAB: \(message)"
        case .invalidRequest(let path):
            return "Invalid YNAB request path: \(path)"
        case .unknown:
            return "Unknown error talking to YNAB."
        }
    }

    /// YNAB error IDs are HTTP-style ("400", "404.1", "429"). Match on the leading status code.
    static func hint(forErrorId id: String) -> String? {
        let status = id.split(separator: ".").first.map(String.init) ?? id
        switch status {
        case "400":
            return "Check parameter formats: dates are YYYY-MM-DD, months are YYYY-MM-01 or 'current', amounts are plain numbers."
        case "401":
            return "The YNAB token is missing, invalid, or revoked. Create a new one at https://app.ynab.com/settings/developer and update YNAB_TOKEN."
        case "403":
            return "The YNAB subscription may have lapsed, or the token lacks access to this plan."
        case "404":
            return "An ID was not found. Use list_plans, list_accounts, list_categories, or list_payees to look up valid IDs."
        case "409":
            return "The resource conflicts with existing data (for example a duplicate import_id)."
        case "429":
            return "YNAB's rate limit (200 requests/hour per token) was hit. Wait before retrying."
        case "500", "503":
            return "YNAB is having trouble. Retry in a minute."
        default:
            return nil
        }
    }
}
