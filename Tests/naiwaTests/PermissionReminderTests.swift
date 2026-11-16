import Foundation
import Testing
@testable import naiwa

struct PermissionReminderTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
    func event(_ name: String, tool: String? = nil, type: String? = nil) -> [String: Any] {
        var e: [String: Any] = ["hook_event_name": name, "session_id": "test",
                               "message": "Claude needs your permission to use Bash"]
        e["tool_use_id"] = tool
        e["notification_type"] = type
        return e
    }

    @Test func reminderExpiresWithoutAnotherHookAndPreservesLongToolDuration() throws {
        let clock = Clock(), start = Date(timeIntervalSince1970: 1_000_000)
        let s = Sessions(now: { clock.now })
        _ = s.handle(event("UserPromptSubmit"))
        _ = s.handle(event("PreToolUse", tool: "long"))
        _ = s.handle(event("Notification", type: "permission_prompt"))
        #expect(s.nextExpiry == start + Sessions.permissionReminderSeconds)
        clock.now = start + Sessions.permissionReminderSeconds - 1
        #expect(s.mood == .waiting)
        clock.now += 1
        #expect(s.mood == .working)
        #expect(s.waitingText == nil)
        #expect(s.all["test"]?.outstandingTools == ["long"])
        #expect(s.nextExpiry == start + Sessions.maxToolSeconds)
        clock.now += 3600
        _ = s.handle(event("PostToolUse", tool: "long"))
        let finished = try #require(s.handle(event("Stop")))
        #expect(finished.seconds == 3600 + Sessions.permissionReminderSeconds)
    }

    @Test func eachParallelReminderHasItsOwnDeadline() {
        let clock = Clock(), s = Sessions()
        s.now = { clock.now }
        let start = clock.now
        _ = s.handle(event("UserPromptSubmit"))
        _ = s.handle(event("PreToolUse", tool: "a"))
        _ = s.handle(event("PreToolUse", tool: "b"))
        _ = s.handle(event("Notification", tool: "a", type: "permission_prompt"))
        clock.now += 30
        _ = s.handle(event("Notification", tool: "b", type: "permission_prompt"))
        clock.now = start + Sessions.permissionReminderSeconds
        #expect(s.mood == .waiting)
        #expect(s.all["test"]?.waiting.keys.sorted() == ["b"])
        #expect(s.nextExpiry == start + 30 + Sessions.permissionReminderSeconds)
    }

    @Test func unrelatedNotificationsDoNotRenewPermissionReminder() {
        let clock = Clock(), s = Sessions()
        s.now = { clock.now }
        _ = s.handle(event("UserPromptSubmit"))
        _ = s.handle(event("PreToolUse", tool: "a"))
        _ = s.handle(event("Notification", type: "permission_prompt"))
        clock.now += Sessions.permissionReminderSeconds - 1
        _ = s.handle(event("Notification", type: "idle_prompt"))
        clock.now += 1
        #expect(s.waitingText == nil)
        #expect(s.mood == .working)
    }

    @Test func replyRequestsRemainWaitingAfterPermissionReminderExpires() {
        let clock = Clock(), s = Sessions()
        s.now = { clock.now }
        _ = s.handle(event("UserPromptSubmit"))
        _ = s.handle(event("PreToolUse", tool: "a"))
        _ = s.handle(event("Notification", tool: "a", type: "permission_prompt"))
        _ = s.handle(event("Notification", tool: "form", type: "elicitation_dialog"))
        clock.now += Sessions.permissionReminderSeconds
        #expect(s.mood == .waiting)
        #expect(s.all["test"]?.waiting.keys.sorted() == ["form"])
        #expect(s.waitingText == "Claude 等你回复")
    }

    @Test func notificationAloneDoesNotInventWorkingStateAfterExpiry() {
        let clock = Clock(), s = Sessions()
        s.now = { clock.now }
        _ = s.handle(event("Notification", type: "permission_prompt"))
        clock.now += Sessions.permissionReminderSeconds
        #expect(s.mood == .idle)
        #expect(s.nextExpiry == nil)
    }

    @Test func legacyPermissionNotificationsHaveTheSameLimit() {
        let clock = Clock(), s = Sessions()
        s.now = { clock.now }
        _ = s.handle(event("UserPromptSubmit"))
        _ = s.handle(event("PreToolUse", tool: "a"))
        _ = s.handle(event("Notification"))
        clock.now += Sessions.permissionReminderSeconds
        #expect(s.mood == .working)
        #expect(s.waitingText == nil)
    }
}
