import Foundation

/// 每个人自己的安排：一天里哪个时段出来哪几只、干活时是哪只。
/// 存在 ~/.config/naiwa/config.json，可以在右键菜单里勾，也可以手改、发给别人；没有这个文件就用素材自带的默认安排。
///   {"idle": [{"from": 0, "pets": ["lonely"]}, {"from": 6, "pets": ["sleep"]}, …], "work": "immerse"}
/// from 是这个时段从几点开始（本地时间，0–23），到下一个时段的 from 为止；同一时段写几只，每回到空闲轮流出来一只。
struct Schedule: Equatable {
    struct Slot: Equatable {
        var from: Int
        var pets: [String]
    }

    var idle: [Slot]
    var work: String

    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/naiwa/config.json")
    }

    /// 从 JSON 读；认不出的名字丢掉，空了的时段丢掉，一个时段都不剩就是读失败
    init?(json j: [String: Any], known: Set<String>) {
        idle = (j["idle"] as? [[String: Any]] ?? []).compactMap { s in
            guard let from = s["from"] as? Int, (0..<24).contains(from) else { return nil }
            let pets = (s["pets"] as? [String] ?? []).filter(known.contains)
            return pets.isEmpty ? nil : Slot(from: from, pets: pets)
        }.sorted { $0.from < $1.from }
        work = j["work"] as? String ?? ""
        if idle.isEmpty { return nil }
    }

    init(idle: [Slot], work: String) {
        self.idle = idle
        self.work = work
    }

    /// 用户的文件 + 默认：文件里没写或者写坏的部分用默认的
    static func load(_ assets: Assets) -> Schedule {
        var s = assets.defaults
        if let data = try? Data(contentsOf: file),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let loops = Set(assets.loopPets)
            if let mine = Schedule(json: j, known: loops) { s.idle = mine.idle }
            if let w = j["work"] as? String, loops.contains(w) { s.work = w }
        }
        return s
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 给人手改的：一个时段一行
        func str(_ v: Any) -> String { String(data: (try? JSONSerialization.data(withJSONObject: v, options: .fragmentsAllowed)) ?? Data(), encoding: .utf8) ?? "\"\"" }
        let slots = idle.map { "    {\"from\": \($0.from), \"pets\": [" + $0.pets.map(str).joined(separator: ", ") + "]}" }
        let text = "{\n  \"idle\": [\n" + slots.joined(separator: ",\n") + "\n  ],\n  \"work\": " + str(work) + "\n}\n"
        try Data(text.utf8).write(to: Self.file, options: .atomic)
    }

    /// 现在这个钟点的时段：from 不超过当前小时的最后一个；还没到第一个的 from，就接着用前一天最后那个
    func slot(at date: Date = Date()) -> Slot {
        let hour = Calendar.current.component(.hour, from: date)
        return idle.last { $0.from <= hour } ?? idle[idle.count - 1]
    }

    /// 下一次换时段的时间
    func nextChange(after date: Date = Date()) -> Date? {
        guard idle.count > 1 else { return nil }
        let cal = Calendar.current
        return idle.compactMap { cal.nextDate(after: date, matching: DateComponents(hour: $0.from, minute: 0, second: 0), matchingPolicy: .nextTime) }.min()
    }

    /// 某个时段里勾上 / 去掉一只（至少留一只）
    mutating func toggle(_ pet: String, inSlotFrom from: Int) {
        guard let i = idle.firstIndex(where: { $0.from == from }) else { return }
        if let k = idle[i].pets.firstIndex(of: pet) {
            if idle[i].pets.count > 1 { idle[i].pets.remove(at: k) }
        } else {
            idle[i].pets.append(pet)
        }
    }
}
