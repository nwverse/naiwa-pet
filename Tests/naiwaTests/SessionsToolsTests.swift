import Foundation
import Testing
@testable import naiwa

struct SessionsToolsTests {
    private let sessionID = "session"

    @Test func testLongRunningToolSurvivesSilenceAndPreservesFinish() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })

        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-long"))
        now.addTimeInterval(1801)

        #expect(sessions.mood == .working)
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-long"])

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-long"))
        guard let finished = sessions.handle(event("Stop")) else {
            Issue.record("Stop should finish the original session")
            return
        }
        #expect(abs(finished.seconds - 1801) <= 0.001)
        #expect(finished.tier == Sessions.tier(seconds: 1801, tools: 1))
        #expect(finished.project == "project")
        #expect(sessions.mood == .idle)
    }

    @Test func testFailedLongRunningToolCompletesAndPreservesFinish() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })

        #expect(Hooks.events.contains { $0.name == "PostToolUseFailure" })
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-failure"))
        now.addTimeInterval(1801)
        _ = sessions.handle(notification("permission_prompt", toolUseID: "tool-failure",
                                         message: "Claude needs your permission to use Bash"))
        #expect(sessions.mood == .waiting)
        _ = sessions.handle(event("PostToolUseFailure", toolUseID: "tool-failure"))

        #expect(sessions.all[sessionID]?.outstandingTools == [])
        #expect(sessions.waitingText == nil)
        guard let finished = sessions.handle(event("Stop")) else {
            Issue.record("Stop should finish a session whose tool failed")
            return
        }
        #expect(abs(finished.seconds - 1801) <= 0.001)
        #expect(finished.tier == Sessions.tier(seconds: 1801, tools: 1))
    }

    @Test func testFailureOnlyCompletesMatchingOutstandingTool() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })

        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-one"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-two"))
        _ = sessions.handle(event("PostToolUseFailure", toolUseID: "tool-one"))

        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-two"])
        now.addTimeInterval(1801)
        #expect(sessions.mood == .working)

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-two"))
        #expect(sessions.all[sessionID]?.outstandingTools == [])
        now.addTimeInterval(1801)
        #expect(sessions.mood == .idle)
    }

    @Test func testAbandonedSessionWithoutOutstandingToolIsPruned() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })

        _ = sessions.handle(event("UserPromptSubmit"))
        now.addTimeInterval(1801)

        #expect(sessions.mood == .idle)
        #expect(sessions.all[sessionID]?.start == nil)
    }

    @Test func testParallelToolCompletionDoesNotClearOtherApproval() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-B"))
        _ = sessions.handle(notification("permission_prompt", toolUseID: "tool-B",
                                         message: "Claude needs your permission to use Bash"))

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-A"))

        #expect(sessions.mood == .waiting)
        #expect(sessions.waitingText == "project 等你批准 Bash")

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-B"))

        #expect(sessions.mood == .working)
        #expect(sessions.waitingText == nil)
    }

    @Test func testAnswerNotificationClearsMatchingRequestAfterOtherToolCompletes() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-B"))
        _ = sessions.handle(notification("elicitation_dialog", requestID: "request-B"))
        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-A"))

        #expect(sessions.mood == .waiting)
        #expect(sessions.waitingText == "project 等你回复")

        _ = sessions.handle(notification("elicitation_response", requestID: "request-B"))

        #expect(sessions.mood == .working)
        #expect(sessions.waitingText == nil)
    }

    @Test func testIDLessApprovalUsesMostRecentPreToolUse() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-B"))
        _ = sessions.handle(notification("permission_prompt",
                                         message: "Claude needs your permission to use Bash"))

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-A"))

        #expect(sessions.mood == .waiting)
        #expect(sessions.waitingText == "project 等你批准 Bash")

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-B"))

        #expect(sessions.mood == .working)
        #expect(sessions.waitingText == nil)
    }

    @Test func testIDLessApprovalClearsWithResidualOutstandingToolAfterFailure() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-residual"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-failed"))
        _ = sessions.handle(event("PostToolUseFailure", toolUseID: "tool-failed"))
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-residual"])

        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-approval"))
        _ = sessions.handle(notification("permission_prompt",
                                         message: "Claude needs your permission to use Bash"))
        #expect(sessions.mood == .waiting)

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-approval"))

        #expect(sessions.waitingText == nil)
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-residual"])
        #expect(sessions.mood == .working)
    }

    @Test func testDeniedApprovalIsReleasedWhenTheNextToolStarts() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-denied"))
        _ = sessions.handle(notification("permission_prompt",
                                         message: "Claude needs your permission to use Bash"))
        #expect(sessions.mood == .waiting)

        // The user denied it: Claude Code sends no PostToolUse for that tool, and the model carries on.
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-next"))

        #expect(sessions.mood == .working)
        #expect(sessions.waitingText == nil)
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-next"])

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-next"))
        #expect(sessions.all[sessionID]?.outstandingTools == [])
    }

    @Test func testRunningParallelToolKeepsAnotherToolsApprovalWhenAThirdStarts() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-B"))
        _ = sessions.handle(notification("permission_prompt", toolUseID: "tool-A",
                                         message: "Claude needs your permission to use Bash"))

        // B is still running, so A may well still be waiting for the user.
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-C"))

        #expect(sessions.mood == .waiting)
        #expect(sessions.waitingText == "project 等你批准 Bash")
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-A", "tool-B", "tool-C"])
    }

    @Test func testStaleLatestToolIDDoesNotPinIdlessWaitAcrossNextTool() {
        let sessions = Sessions()
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-A"))
        _ = sessions.handle(notification("elicitation_dialog"))
        #expect(sessions.mood == .waiting)

        // The dialog was answered without a clearing event; the next tool must release it.
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-B"))

        #expect(sessions.mood == .working)
        #expect(sessions.waitingText == nil)
    }

    @Test func testInterruptedToolIsDroppedAfterTheHardCap() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-killed"))

        // Claude was killed mid-tool: no PostToolUse, no Stop, nothing for ten hours.
        now.addTimeInterval(10 * 3600)

        #expect(sessions.mood == .idle)
        #expect(sessions.all[sessionID]?.outstandingTools == [])
    }

    @Test func testToolJustUnderTheHardCapIsKept() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-long"))
        now.addTimeInterval(Sessions.maxToolSeconds - 60)

        #expect(sessions.mood == .working)
        #expect(sessions.all[sessionID]?.outstandingTools == ["tool-long"])

        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-long"))
        guard let finished = sessions.handle(event("Stop")) else {
            Issue.record("Stop should finish the original session")
            return
        }
        #expect(abs(finished.seconds - Sessions.maxToolSeconds - 60) <= 0.001)
    }

    @Test func testDeniedToolNextToRunningToolIsDroppedByTheHardCap() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = Sessions(now: { now })
        _ = sessions.handle(event("UserPromptSubmit"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-denied"))
        _ = sessions.handle(event("PreToolUse", toolUseID: "tool-running"))
        _ = sessions.handle(notification("permission_prompt", toolUseID: "tool-denied",
                                         message: "Claude needs your permission to use Bash"))
        _ = sessions.handle(event("PostToolUse", toolUseID: "tool-running"))
        #expect(sessions.mood == .waiting)

        now.addTimeInterval(Sessions.maxToolSeconds + 1)

        #expect(sessions.mood == .idle)
        #expect(sessions.waitingText == nil)
    }

    private func event(_ name: String, toolUseID: String? = nil) -> [String: Any] {
        var event: [String: Any] = [
            "hook_event_name": name,
            "session_id": sessionID,
            "cwd": "/tmp/example/project",
        ]
        event["tool_use_id"] = toolUseID
        return event
    }

    private func notification(_ type: String, toolUseID: String? = nil, requestID: String? = nil,
                              message: String = "") -> [String: Any] {
        var extra: [String: Any] = ["notification_type": type, "message": message]
        if let toolUseID { extra["tool_use_id"] = toolUseID }
        if let requestID { extra["request_id"] = requestID }
        return event("Notification").merging(extra) { $1 }
    }
}
