import Foundation
import MCP
import SwiftYNAB

/// One MCP tool: its definition, whether it writes to YNAB, and its handler.
public struct ToolSpec: Sendable {
    public typealias Handler = @Sendable ([String: Value], YNABClient) async throws -> CallTool.Result

    public let tool: Tool
    public let handler: Handler

    public var isWrite: Bool { tool.annotations.readOnlyHint != true }

    init(
        name: String,
        title: String,
        description: String,
        inputSchema: Value,
        annotations: Tool.Annotations,
        handler: @escaping Handler
    ) {
        var annotations = annotations
        annotations.title = title
        self.tool = Tool(
            name: name,
            title: title,
            description: description,
            inputSchema: inputSchema,
            annotations: annotations
        )
        self.handler = handler
    }
}

public enum ToolHandlers {

    // MARK: - Registry

    public static let allSpecs: [ToolSpec] = readSpecs + writeSpecs

    public static var allTools: [Tool] { allSpecs.map(\.tool) }

    /// Tools to advertise. In read-only mode write tools are not listed at all.
    public static func tools(readOnly: Bool) -> [Tool] {
        allSpecs.filter { !readOnly || !$0.isWrite }.map(\.tool)
    }

    static let specsByName: [String: ToolSpec] = Dictionary(
        uniqueKeysWithValues: allSpecs.map { ($0.tool.name, $0) }
    )

    // MARK: - Call Routing

    public static func handleCall(
        name: String,
        arguments: [String: Value]?,
        client: YNABClient,
        readOnly: Bool = false
    ) async -> CallTool.Result {
        guard let spec = specsByName[name] else {
            return errorResult("Unknown tool: \(name)")
        }
        do {
            if readOnly && spec.isWrite {
                throw YNABMCPError.readOnlyMode(tool: name)
            }
            return try await spec.handler(arguments ?? [:], client)
        } catch {
            return errorResult(ErrorFormatter.message(for: error))
        }
    }

    // MARK: - Results

    static func textResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    static func errorResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }

    // MARK: - Parameter Helpers

    static func planId(_ args: [String: Value], client: YNABClient) -> String {
        if let id = args["plan_id"]?.stringValue, !id.isEmpty {
            return id
        }
        return client.defaultPlanId
    }

    public static func requireString(_ args: [String: Value], key: String) throws -> String {
        guard let value = args[key]?.stringValue, !value.isEmpty else {
            throw YNABMCPError.missingParameter(key)
        }
        return value
    }

    public static func optionalDouble(_ args: [String: Value], key: String) throws -> Double? {
        guard let value = args[key], !value.isNull else { return nil }
        if let d = value.doubleValue { return d }
        if let i = value.intValue { return Double(i) }
        throw YNABMCPError.invalidParameter(key, detail: "must be a number")
    }

    public static func requireDouble(_ args: [String: Value], key: String) throws -> Double {
        guard let value = try optionalDouble(args, key: key) else {
            throw YNABMCPError.missingParameter(key)
        }
        return value
    }

    public static func optionalBool(_ args: [String: Value], key: String) throws -> Bool? {
        guard let value = args[key], !value.isNull else { return nil }
        guard let bool = value.boolValue else {
            throw YNABMCPError.invalidParameter(key, detail: "must be true or false")
        }
        return bool
    }

    public static func requireStringArray(_ args: [String: Value], key: String) throws -> [String] {
        guard let arrayValue = args[key]?.arrayValue else {
            throw YNABMCPError.missingParameter(key)
        }
        let strings = arrayValue.compactMap(\.stringValue)
        guard !strings.isEmpty, strings.count == arrayValue.count else {
            throw YNABMCPError.invalidParameter(key, detail: "must be a non-empty array of strings")
        }
        return strings
    }

    /// Returns nil when absent; throws on an unrecognized value instead of silently ignoring it.
    public static func parseFlagColor(_ string: String?) throws -> FlagColor? {
        guard let string else { return nil }
        switch string.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "none", "": return FlagColor.none
        default:
            throw YNABMCPError.invalidParameter(
                "flag_color", detail: "'\(string)' is not one of red, orange, yellow, green, blue, purple, none"
            )
        }
    }

    /// Returns nil when absent; throws on an unrecognized value instead of silently ignoring it.
    public static func parseClearedStatus(_ string: String?) throws -> ClearedStatus? {
        guard let string else { return nil }
        switch string.lowercased() {
        case "cleared": return .cleared
        case "reconciled": return .reconciled
        case "uncleared": return .uncleared
        default:
            throw YNABMCPError.invalidParameter(
                "cleared", detail: "'\(string)' is not one of cleared, uncleared, reconciled"
            )
        }
    }

    /// Local time zone on purpose: SwiftYNAB formats `since_date`/`until_date` in the current time zone,
    /// so parsing in UTC would shift every date one day earlier west of UTC.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.isLenient = false
        return formatter
    }()

    public static func parseDate(_ string: String?) -> Date? {
        guard let string, string.count == 10 else { return nil }
        return dateFormatter.date(from: string)
    }

    /// Format a date as YYYY-MM-DD in the local time zone (the inverse of `parseDate`).
    public static func isoDay(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Parse an optional YYYY-MM-DD argument, throwing if it is present but malformed.
    public static func optionalDate(_ args: [String: Value], key: String) throws -> Date? {
        guard let raw = args[key]?.stringValue else { return nil }
        guard let date = parseDate(raw) else {
            throw YNABMCPError.invalidParameter(key, detail: "'\(raw)' is not a valid YYYY-MM-DD date")
        }
        return date
    }

    /// Validate a required YYYY-MM-DD argument and return it as the string YNAB expects.
    public static func requireDateString(_ args: [String: Value], key: String) throws -> String {
        let raw = try requireString(args, key: key)
        guard parseDate(raw) != nil else {
            throw YNABMCPError.invalidParameter(key, detail: "'\(raw)' is not a valid YYYY-MM-DD date")
        }
        return raw
    }

    /// Accept 'current' or a YYYY-MM-01 month.
    public static func requireMonth(_ args: [String: Value], key: String = "month") throws -> String {
        let raw = try requireString(args, key: key)
        if raw.lowercased() == "current" { return "current" }
        guard parseDate(raw) != nil, raw.hasSuffix("-01") else {
            throw YNABMCPError.invalidParameter(key, detail: "'\(raw)' must be 'current' or YYYY-MM-01")
        }
        return raw
    }
}
