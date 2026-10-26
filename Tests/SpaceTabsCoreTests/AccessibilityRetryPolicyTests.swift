import Testing

@testable import SpaceTabsCore

@Test func axFailuresBackOffPerAppWithoutPreventingOtherApplications() {
    var policy = AccessibilityRetryPolicy()
    for (time, delay) in [(0.0, 2.0), (2, 4), (6, 8), (14, 16), (30, 30), (60, 30)] {
        #expect(policy.canAttempt("godot", now: time))
        policy.failed("godot", now: time)
        #expect(!policy.canAttempt("godot", now: time + delay - 0.01))
        #expect(policy.canAttempt("godot", now: time + delay))
        #expect(policy.canAttempt("chrome", now: time))
    }
    policy.succeeded("godot")
    #expect(policy.canAttempt("godot", now: 60))
}

@Test func unsupportedNotificationsWaitUntilExplicitRefreshOrProcessRestart() {
    var policy = AccessibilityRetryPolicy()
    policy.failed("10:created", now: 0, unsupported: true)
    policy.failed("20:created", now: 0)
    #expect(!policy.canAttempt("10:created", now: 100_000))
    policy.reset(prefix: "10:")
    #expect(policy.canAttempt("10:created", now: 0))
    #expect(!policy.canAttempt("20:created", now: 0))
    policy.reset()
    #expect(policy.canAttempt("20:created", now: 0))
}
