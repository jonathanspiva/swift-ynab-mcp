import Testing
@testable import YNABMCPLib

@Suite("Formatters")
struct FormattersTests {

    // MARK: - dollars(from:)

    @Test("Converts positive milliunits to dollars")
    func dollarsPositive() {
        #expect(Formatters.dollars(from: 50000) == "$50.00")
    }

    @Test("Converts negative milliunits to dollars")
    func dollarsNegative() {
        #expect(Formatters.dollars(from: -50000) == "-$50.00")
    }

    @Test("Converts zero milliunits to dollars")
    func dollarsZero() {
        #expect(Formatters.dollars(from: 0) == "$0.00")
    }

    @Test("Converts fractional milliunits correctly")
    func dollarsFractional() {
        // 12340 milliunits = $12.34
        #expect(Formatters.dollars(from: 12340) == "$12.34")
    }

    @Test("Converts large amounts with comma grouping")
    func dollarsLargeAmount() {
        // 1_234_567_890 milliunits = $1,234,567.89
        #expect(Formatters.dollars(from: 1_234_567_890) == "$1,234,567.89")
    }

    @Test("Converts single digit cents")
    func dollarsSingleDigitCents() {
        // 1050 milliunits = $1.05
        #expect(Formatters.dollars(from: 1050) == "$1.05")
    }

    @Test("Handles sub-dollar amount")
    func dollarsSubDollar() {
        #expect(Formatters.dollars(from: 990) == "$0.99")
    }

    // MARK: - milliunits(from:)

    @Test("Converts positive dollars to milliunits")
    func milliunitsPositive() {
        #expect(Formatters.milliunits(from: 50.0) == 50000)
    }

    @Test("Converts negative dollars to milliunits")
    func milliunitsNegative() {
        #expect(Formatters.milliunits(from: -50.0) == -50000)
    }

    @Test("Converts zero dollars to milliunits")
    func milliunitsZero() {
        #expect(Formatters.milliunits(from: 0.0) == 0)
    }

    @Test("Converts fractional dollars to milliunits")
    func milliunitsFractional() {
        #expect(Formatters.milliunits(from: 12.34) == 12340)
    }

    @Test("Rounds sub-milliunit amounts correctly")
    func milliunitsRounding() {
        // 12.345 * 1000 = 12345.0, rounds to 12345
        #expect(Formatters.milliunits(from: 12.345) == 12345)
        // 12.3454 * 1000 = 12345.4, rounds to 12345
        #expect(Formatters.milliunits(from: 12.3454) == 12345)
        // 12.3455 * 1000 = 12345.5, rounds to 12346
        #expect(Formatters.milliunits(from: 12.3455) == 12346)
    }

    @Test("Round-trips dollars through milliunits and back")
    func roundTrip() {
        let original = -42.50
        let milliunits = Formatters.milliunits(from: original)
        let formatted = Formatters.dollars(from: milliunits)
        #expect(formatted == "-$42.50")
    }

    // MARK: - escapeTableCell

    @Test("Escapes pipe characters in table cells")
    func escapeTableCellWithPipes() {
        #expect(Formatters.escapeTableCell("Food | Drink") == "Food \\| Drink")
    }

    @Test("Returns unchanged string without pipes")
    func escapeTableCellNoPipes() {
        #expect(Formatters.escapeTableCell("Groceries") == "Groceries")
    }

    @Test("Handles empty string")
    func escapeTableCellEmpty() {
        #expect(Formatters.escapeTableCell("") == "")
    }

    @Test("Handles multiple pipes")
    func escapeTableCellMultiplePipes() {
        #expect(Formatters.escapeTableCell("a|b|c") == "a\\|b\\|c")
    }
}
