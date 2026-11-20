import Testing
import SwiftYNAB
@testable import YNABMCPLib

@Suite("Errors")
struct YNABMCPErrorTests {

    @Test("Local errors have descriptive messages")
    func localErrorDescriptions() {
        #expect(YNABMCPError.rateLimited(remaining: 0).description.contains("200 requests"))
        #expect(YNABMCPError.missingParameter("plan_id").description.contains("plan_id"))
        let invalid = YNABMCPError.invalidParameter("date", detail: "must be YYYY-MM-DD")
        #expect(invalid.description.contains("date") && invalid.description.contains("YYYY-MM-DD"))
        #expect(YNABMCPError.readOnlyMode(tool: "create_transaction").description.contains("YNAB_READ_ONLY"))
        #expect(invalid.errorDescription == invalid.description)
    }

    @Test("YNAB API errors include detail and an actionable hint")
    func apiErrorWithHint() {
        let error = SwiftYNABError.apiError(detail: ErrorDetail(id: "404.2", name: "resource_not_found", detail: "Resource not found"))
        let message = ErrorFormatter.message(for: error)
        #expect(message.contains("404.2"))
        #expect(message.contains("Resource not found"))
        #expect(message.contains("list_categories"))
    }

    @Test("401 points at the token")
    func unauthorizedHint() {
        let message = ErrorFormatter.message(for: SwiftYNABError.httpError(statusCode: 401))
        #expect(message.contains("YNAB_TOKEN"))
    }

    @Test("Unknown status codes still produce a message without a hint")
    func unknownStatus() {
        let message = ErrorFormatter.message(for: SwiftYNABError.httpError(statusCode: 418))
        #expect(message.contains("418"))
        #expect(!message.contains("Hint"))
    }

    @Test("Hint lookup matches on the leading status code")
    func hintLookup() {
        #expect(ErrorFormatter.hint(forErrorId: "429") != nil)
        #expect(ErrorFormatter.hint(forErrorId: "404.1") == ErrorFormatter.hint(forErrorId: "404"))
        #expect(ErrorFormatter.hint(forErrorId: "999") == nil)
    }
}
