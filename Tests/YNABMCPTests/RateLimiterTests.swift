import Testing
@testable import YNABMCPLib

@Suite("RateLimiter")
struct RateLimiterTests {

    @Test("Allows requests under the limit")
    func allowsUnderLimit() async {
        let limiter = RateLimiter(maxRequests: 5, windowSeconds: 60)

        for _ in 0..<5 {
            let allowed = await limiter.allowRequest()
            #expect(allowed)
        }
    }

    @Test("Denies requests at the limit")
    func deniesAtLimit() async {
        let limiter = RateLimiter(maxRequests: 3, windowSeconds: 60)

        for _ in 0..<3 {
            _ = await limiter.allowRequest()
        }

        let denied = await limiter.allowRequest()
        #expect(!denied)
    }

    @Test("Reports correct remaining count")
    func remainingCount() async {
        let limiter = RateLimiter(maxRequests: 10, windowSeconds: 60)

        let initialRemaining = await limiter.remaining
        #expect(initialRemaining == 10)

        _ = await limiter.allowRequest()
        _ = await limiter.allowRequest()
        _ = await limiter.allowRequest()

        let afterThree = await limiter.remaining
        #expect(afterThree == 7)
    }

    @Test("Remaining is zero when at limit")
    func remainingZero() async {
        let limiter = RateLimiter(maxRequests: 2, windowSeconds: 60)

        _ = await limiter.allowRequest()
        _ = await limiter.allowRequest()

        let remaining = await limiter.remaining
        #expect(remaining == 0)
    }

    @Test("Uses default values of 200 requests per hour")
    func defaultValues() async {
        let limiter = RateLimiter()
        let remaining = await limiter.remaining
        #expect(remaining == 200)
    }

    @Test("Expired timestamps are cleaned up")
    func expiredTimestampCleanup() async {
        // Use a very short window so timestamps expire immediately
        let limiter = RateLimiter(maxRequests: 2, windowSeconds: 0.001)

        _ = await limiter.allowRequest()
        _ = await limiter.allowRequest()

        // Wait for the window to expire
        try? await Task.sleep(for: .milliseconds(10))

        // Should be allowed again after expiry
        let allowed = await limiter.allowRequest()
        #expect(allowed)
    }
}
