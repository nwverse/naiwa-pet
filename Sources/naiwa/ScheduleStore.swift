import Foundation

/// 显示只用认识的奶蛙，写盘只改菜单选中的字段；不能把过滤后的安排整份覆盖回去。
final class ScheduleStore {
    enum Edit { case toggle(String, from: Int), work(String) }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private let defaults: Schedule
    private let known: Set<String>
    let file: URL
    private var lastData: Data?
    private(set) var current: Schedule

    init(defaults: Schedule, known: Set<String>, file: URL = Schedule.file) {
        self.defaults = defaults
        self.known = known
        self.file = file
        current = defaults
        _ = reload()
    }

    private func read() throws -> Data? {
        do { return try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func document(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("配置必须是 JSON 对象；原文件未修改。")
        }
        return j
    }

    private func resolve(_ j: [String: Any]) -> Schedule {
        var s = defaults
        if let mine = Schedule(json: j, known: known) { s.idle = mine.idle }
        if let work = j["work"] as? String, canWork(work) { s.work = work }
        return s
    }

    /// 干活时能填的：认识的奶蛙，或者「跟着时段」
    private func canWork(_ name: String) -> Bool { known.contains(name) || name == Schedule.followSlot }

    /// 编辑器写到一半、JSON 暂时不完整时保留当前安排；删除文件则恢复默认。
    @discardableResult func reload() -> Schedule {
        do {
            let data = try read()
            if data != lastData {
                let j = try document(data)
                current = resolve(j)
                lastData = data
            }
        } catch { /* 读不了或还没写完，不用默认配置打断正在运行的安排 */ }
        return current
    }

    @discardableResult func apply(_ edit: Edit) throws -> Schedule {
        let original = try read() // 菜单打开后也可能又被手改，必须从磁盘的最新内容开始。
        var j = try document(original)
        switch edit {
        case .work(let name):
            guard canWork(name) else { throw Failure("找不到这只奶蛙。") }
            j["work"] = name
        case .toggle(let name, let from):
            guard known.contains(name) else { throw Failure("找不到这只奶蛙。") }
            var rows: [Any]
            if let raw = j["idle"] {
                guard let slots = raw as? [Any], Schedule(json: j, known: known) != nil else {
                    throw Failure("空闲时段无法编辑；请先修复配置，原文件未修改。")
                }
                rows = slots
            } else {
                rows = defaults.idle.map { ["from": $0.from, "pets": $0.pets] as [String: Any] }
            }
            let matches = rows.indices.filter { (rows[$0] as? [String: Any])?["from"] as? Int == from }
            guard matches.count == 1, let i = matches.first,
                  var row = rows[i] as? [String: Any], var pets = row["pets"] as? [String],
                  !pets.filter(known.contains).isEmpty else {
                throw Failure("这个时段已变化或无法编辑；请重新打开菜单，原文件未修改。")
            }
            if pets.contains(name) {
                // 未知名字不算可播放候选，不能删掉最后一只已知奶蛙。
                if Set(pets.filter(known.contains)).count > 1 { pets.removeAll { $0 == name } }
            } else {
                pets.append(name)
            }
            row["pets"] = pets
            rows[i] = row
            j["idle"] = rows
        }
        try write(j, replacing: original)
        return reload()
    }

    func createIfMissing() throws {
        guard try read() == nil else { return }
        try write(["idle": defaults.idle.map { ["from": $0.from, "pets": $0.pets] as [String: Any] },
                   "work": defaults.work], replacing: nil)
    }

    private func write(_ j: [String: Any], replacing original: Data?) throws {
        let target = file.resolvingSymlinksInPath()
        let data = try JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mode = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        guard try read() == original, file.resolvingSymlinksInPath() == target else {
            throw Failure("配置刚被其他程序修改，请重新打开菜单；原文件未修改。")
        }
        try (data + Data("\n".utf8)).write(to: target, options: .atomic)
        if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
    }
}
