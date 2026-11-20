import Testing
@testable import YNABMCPLib

@Suite("ServerConfig")
struct ServerConfigTests {

    @Test("Missing or blank token yields nil")
    func missingToken() {
        #expect(ServerConfig(environment: [:]) == nil)
        #expect(ServerConfig(environment: ["YNAB_TOKEN": "  "]) == nil)
    }

    @Test("Defaults: last-used plan, read-write")
    func defaults() throws {
        let config = try #require(ServerConfig(environment: ["YNAB_TOKEN": " abc\n"]))
        #expect(config.token == "abc")
        #expect(config.defaultPlanId == "last-used")
        #expect(config.readOnly == false)
    }

    @Test("YNAB_PLAN_ID overrides the default plan")
    func planOverride() throws {
        let config = try #require(ServerConfig(environment: ["YNAB_TOKEN": "t", "YNAB_PLAN_ID": "plan-1"]))
        #expect(config.defaultPlanId == "plan-1")
    }

    @Test("YNAB_READ_ONLY accepts common truthy values", arguments: ["1", "true", "TRUE", "yes", "on"])
    func readOnlyTruthy(value: String) throws {
        let config = try #require(ServerConfig(environment: ["YNAB_TOKEN": "t", "YNAB_READ_ONLY": value]))
        #expect(config.readOnly)
    }

    @Test("YNAB_READ_ONLY falsy values stay read-write", arguments: ["0", "false", "", "no"])
    func readOnlyFalsy(value: String) throws {
        let config = try #require(ServerConfig(environment: ["YNAB_TOKEN": "t", "YNAB_READ_ONLY": value]))
        #expect(!config.readOnly)
    }

    @Test("Instructions reflect mode and default plan")
    func instructions() {
        let readOnly = ServerInfo.instructions(readOnly: true, defaultPlanId: "last-used")
        #expect(readOnly.contains("read-only"))
        #expect(readOnly.contains("last-used"))
        let readWrite = ServerInfo.instructions(readOnly: false, defaultPlanId: "p1")
        #expect(readWrite.contains("live budget"))
        #expect(readWrite.contains("p1"))
    }
}
