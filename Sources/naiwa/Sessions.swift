import Foundation

/// 根据 Claude Code 的 hook 事件给每个会话记账，判断奶蛙该是什么状态、一轮结束时值不值得瞥你一眼。
/// 全在本地算，不调模型。
final class Sessions {
    enum Mood { case idle, working, waiting }
    enum Tier { case none, big, huge }

    struct Session {
        var cwd: String
        var start: Date?          // 这一轮开始干活的时间（用户发消息，或者第一次调工具）
        var tools = 0             // 这一轮调了几次工具
        var waiting: String?      // 在等你批准什么
        var stopped: (start: Date?, tools: Int, glanced: Bool)?   // 上次 Stop 停下时这一轮的账：别的 Stop hook 可能拦下来让它接着干
        var seen = Date()
    }

    struct Finished {
        let tier: Tier
        let project: String
        let seconds: TimeInterval
    }

    private(set) var all: [String: Session] = [:]

    var mood: Mood {
        prune()
        if all.values.contains(where: { $0.waiting != nil }) { return .waiting }
        if all.values.contains(where: { $0.start != nil }) { return .working }
        return .idle
    }

    /// 等你的那个会话：项目名和在等什么
    var waitingText: String? {
        guard let s = all.values.filter({ $0.waiting != nil }).max(by: { $0.seen < $1.seen }) else { return nil }
        return "\(Self.project(s.cwd)) \(s.waiting!)"
    }

    /// 处理一条 hook 事件；一轮结束时返回这一轮的结果。now 给测试用
    func handle(_ e: [String: Any], now: Date = Date()) -> Finished? {
        guard let event = e["hook_event_name"] as? String, let id = e["session_id"] as? String else { return nil }
        var s = all[id] ?? Session(cwd: e["cwd"] as? String ?? "")
        if let cwd = e["cwd"] as? String { s.cwd = cwd }
        s.seen = now
        var finished: Finished?
        switch event {
        case "UserPromptSubmit":
            s.start = now
            s.tools = 0
            s.waiting = nil
            s.stopped = nil
        case "PreToolUse":
            s.waiting = nil
            s.tools += 1
            if s.start == nil { s.start = now }
        case "PostToolUse", "PostToolUseFailure":
            s.waiting = nil
        case "Notification":
            switch Self.notification(type: e["notification_type"] as? String, message: e["message"] as? String ?? "") {
            case .waiting(let text): s.waiting = text
            case .answered: s.waiting = nil
            case .ignore: break
            }
        case "Stop":
            // 别的 Stop hook 拦下结束（decision: block）时 Claude 接着干同一轮，再停时带 stop_hook_active: true：
            // 接上停下前的账，时长从最开始算、工具次数累加，一轮最多瞥一次
            var glanced = false
            if e["stop_hook_active"] as? Bool == true, let p = s.stopped {
                s.start = p.start ?? s.start
                s.tools += p.tools
                glanced = p.glanced
            }
            // naiwa_seconds：`naiwa demo` 用来假装这一轮跑了多久
            let seconds = e["naiwa_seconds"] as? Double ?? s.start.map { now.timeIntervalSince($0) } ?? 0
            let tier = glanced ? .none : Self.tier(seconds: seconds, tools: s.tools)
            finished = Finished(tier: tier, project: Self.project(s.cwd), seconds: seconds)
            s.stopped = (s.start, s.tools, glanced || tier != .none)
            s.start = nil
            s.tools = 0
            s.waiting = nil
        case "SessionEnd":
            all[id] = nil
            return nil
        default:
            break
        }
        all[id] = s
        return finished
    }

    /// 跑满 bigSeconds 且动过工具才算干完一个活；跑满 hugeSeconds 算超长任务。只聊了几句不算
    static func tier(seconds: TimeInterval, tools: Int) -> Tier {
        guard tools > 0, seconds >= Prefs.bigSeconds else { return .none }
        return seconds >= Prefs.hugeSeconds ? .huge : .big
    }

    enum NotificationKind { case waiting(String), answered, ignore }

    /// 只有真的卡在你身上才算「等你」：要权限、MCP 弹表单问你、后台会话等你回话。
    /// Claude 说完 60 秒你没理它（idle_prompt）、登录成功之类都不算，不然做完的会话放着不管，奶蛙会一直盯着你。
    static func notification(type: String?, message: String) -> NotificationKind {
        switch type {
        case "permission_prompt":
            return .waiting(permissionText(message))
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            return .waiting("等你回复")
        case "elicitation_complete", "elicitation_response":
            return .answered
        case .some:
            return .ignore
        case nil:
            // 老版本 Claude Code 没有 notification_type：只认明确提到权限的
            return message.localizedCaseInsensitiveContains("permission") ? .waiting(permissionText(message)) : .ignore
        }
    }

    /// 「Claude needs your permission to use Bash」→「等你批准 Bash」
    static func permissionText(_ message: String) -> String {
        guard let r = message.range(of: #"permission to use (\S+)"#, options: .regularExpression),
              let tool = message[r].split(separator: " ").last else { return "等你批准" }
        return "等你批准 \(tool)"
    }

    static func project(_ cwd: String) -> String {
        if cwd.isEmpty { return "Claude" }
        if cwd == FileManager.default.homeDirectoryForCurrentUser.path { return "~" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) 秒" }
        if s < 3600 { return "\(s / 60) 分 \(s % 60) 秒" }
        return "\(s / 3600) 小时 \(s % 3600 / 60) 分"
    }

    /// 会话没收到 Stop 就没了（Claude 被杀掉之类），半小时没动静就不算它还在干活
    private func prune() {
        let now = Date()
        for (id, s) in all where (s.start != nil || s.waiting != nil) && now.timeIntervalSince(s.seen) > 1800 {
            all[id]?.start = nil
            all[id]?.waiting = nil
        }
    }
}
