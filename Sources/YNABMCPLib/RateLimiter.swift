import Foundation

public actor RateLimiter {
    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var timestamps: [Date] = []

    public init(maxRequests: Int = 200, windowSeconds: TimeInterval = 3600) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    /// Check if a request is allowed. Returns true if under the limit.
    public func allowRequest() -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSeconds)

        // Remove expired timestamps
        timestamps.removeAll { $0 < cutoff }

        if timestamps.count >= maxRequests {
            return false
        }

        timestamps.append(now)
        return true
    }

    /// Number of remaining requests in the current window
    public var remaining: Int {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let active = timestamps.filter { $0 >= cutoff }
        return max(0, maxRequests - active.count)
    }
}
