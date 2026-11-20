import MCP

/// Small builders for JSON Schema `Value`s so tool definitions stay readable.
enum Schema {
    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    static func string(_ description: String, oneOf values: [String]? = nil) -> Value {
        var schema: [String: Value] = ["type": "string", "description": .string(description)]
        if let values {
            schema["enum"] = .array(values.map { .string($0) })
        }
        return .object(schema)
    }

    static func date(_ description: String) -> Value {
        .object([
            "type": "string",
            "description": .string("\(description) (YYYY-MM-DD)"),
            "pattern": #"^\d{4}-\d{2}-\d{2}$"#,
        ])
    }

    static func number(_ description: String) -> Value {
        .object(["type": "number", "description": .string(description)])
    }

    static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> Value {
        var schema: [String: Value] = ["type": "integer", "description": .string(description)]
        if let minimum { schema["minimum"] = .int(minimum) }
        if let maximum { schema["maximum"] = .int(maximum) }
        return .object(schema)
    }

    static func boolean(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    static func stringArray(_ description: String, minItems: Int = 1) -> Value {
        .object([
            "type": "array",
            "items": .object(["type": "string"]),
            "minItems": .int(minItems),
            "description": .string(description),
        ])
    }

    // MARK: - Shared properties

    static let planId = string(
        "Plan (budget) ID. Optional: defaults to the last-used plan, or YNAB_PLAN_ID if set. Use list_plans to see IDs."
    )

    static let month = string(
        "Month as YYYY-MM-01 (first day of the month) or 'current'"
    )

    static let amount = number(
        "Amount in the plan's currency units, e.g. -42.50. Negative is an outflow (spending), positive is an inflow."
    )

    static let flagColor = string(
        "Flag color, or 'none' to clear the flag",
        oneOf: ["red", "orange", "yellow", "green", "blue", "purple", "none"]
    )

    static let cleared = string(
        "Cleared status",
        oneOf: ["cleared", "uncleared", "reconciled"]
    )
}
