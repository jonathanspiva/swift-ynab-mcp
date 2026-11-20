import Testing
@testable import YNABMCPLib

@Suite("Formatters")
struct FormattersTests {

    // MARK: - money(_:formatted:)

    @Test("Prefers YNAB's formatted string when present")
    func moneyUsesFormatted() {
        #expect(Formatters.money(50000, formatted: "€50,00") == "€50,00")
    }

    @Test("Falls back to plain number when formatted is nil or empty", arguments: [
        (50000, "50.00"),
        (-50000, "-50.00"),
        (0, "0.00"),
        (12340, "12.34"),
        (1050, "1.05"),
        (990, "0.99"),
        (1_234_567_890, "1,234,567.89"),
        (12345, "12.345"),
    ])
    func moneyFallback(milliunits: Int, expected: String) {
        #expect(Formatters.money(milliunits) == expected)
        #expect(Formatters.money(milliunits, formatted: "") == expected)
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

    @Test("Round-trips amounts through milliunits and back")
    func roundTrip() {
        let original = -42.50
        let milliunits = Formatters.milliunits(from: original)
        #expect(Formatters.money(milliunits) == "-42.50")
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

    @Test("Flattens newlines in table cells")
    func escapeTableCellNewlines() {
        #expect(Formatters.escapeTableCell("line one\nline two") == "line one line two")
    }

    @Test("Handles multiple pipes")
    func escapeTableCellMultiplePipes() {
        #expect(Formatters.escapeTableCell("a|b|c") == "a\\|b\\|c")
    }
}
