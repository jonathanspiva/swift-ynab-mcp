import Testing
@testable import YNABMCPLib

@Suite("YNABMCPError")
struct YNABMCPErrorTests {

    @Test("Rate limited error has descriptive message")
    func rateLimitedDescription() {
        let error = YNABMCPError.rateLimited(remaining: 5)
        #expect(error.description.contains("Rate limit"))
        #expect(error.description.contains("5"))
    }

    @Test("Missing parameter error includes parameter name")
    func missingParameterDescription() {
        let error = YNABMCPError.missingParameter("budget_id")
        #expect(error.description.contains("budget_id"))
        #expect(error.description.contains("Missing"))
    }

    @Test("Invalid parameter error includes name and detail")
    func invalidParameterDescription() {
        let error = YNABMCPError.invalidParameter("date", detail: "must be YYYY-MM-DD")
        #expect(error.description.contains("date"))
        #expect(error.description.contains("YYYY-MM-DD"))
    }

    @Test("LocalizedError.errorDescription matches description")
    func localizedErrorConformance() {
        let error = YNABMCPError.missingParameter("test")
        #expect(error.errorDescription == error.description)
    }

    @Test("Error is surfaced correctly via string interpolation")
    func errorStringInterpolation() {
        let error = YNABMCPError.missingParameter("budget_id")
        let message = "Error: \(error)"
        #expect(message.contains("budget_id"))
    }
}
