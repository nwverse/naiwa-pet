import Foundation
import Testing
@testable import naiwa

struct ScheduleStoreTests {
    let defaults = Schedule(idle: [.init(from: 0, pets: ["sleep", "listen"])], work: "sleep")

    func withStore(_ text: String?, _ body: (ScheduleStore, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        if let text { try Data(text.utf8).write(to: file) }
        try body(ScheduleStore(defaults: defaults, known: ["sleep", "listen"], file: file), file)
    }

    func json(_ file: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func togglePreservesUnknownNamesSlotsAndFields() throws {
        try withStore(#"{"idle":[{"from":0,"pets":["sleep","future","listen"],"label":"keep"},{"from":12,"pets":["future"],"v2":true}],"work":"future","extra":{"x":1}}"#) { store, file in
            _ = try store.apply(.toggle("listen", from: 0))
            let j = try json(file)
            let rows = try #require(j["idle"] as? [[String: Any]])
            #expect(rows.count == 2)
            #expect(rows[0]["pets"] as? [String] == ["sleep", "future"])
            #expect(rows[0]["label"] as? String == "keep")
            #expect(rows[1]["pets"] as? [String] == ["future"])
            #expect(rows[1]["v2"] as? Bool == true)
            #expect(j["work"] as? String == "future")
            #expect((j["extra"] as? [String: Int])?["x"] == 1)
        }
    }

    @Test func menuActionReadsEditsMadeAfterMenuOpened() throws {
        try withStore(#"{"work":"sleep"}"#) { store, file in
            try Data(#"{"idle":[{"from":12,"pets":["listen"]}],"work":"future","keep":7}"#.utf8).write(to: file)
            let s = try store.apply(.work("sleep"))
            #expect(s.idle == [.init(from: 12, pets: ["listen"])])
            #expect(try json(file)["keep"] as? Int == 7)
        }
    }

    @Test func invalidJSONKeepsCurrentScheduleAndCannotBeOverwritten() throws {
        try withStore(#"{"idle":[{"from":8,"pets":["listen"]}],"work":"listen"}"#) { store, file in
            let before = store.current
            let broken = Data(#"{"idle": ["#.utf8)
            try broken.write(to: file)
            #expect(store.reload() == before)
            #expect(throws: (any Error).self) { try store.apply(.work("sleep")) }
            #expect(try Data(contentsOf: file) == broken)
            try FileManager.default.removeItem(at: file)
            #expect(store.reload() == defaults)
        }
    }

    @Test func unknownOnlyScheduleIsPreservedWhenItCannotBeEdited() throws {
        let text = #"{"idle":[{"from":0,"pets":["future"]}]}"#
        try withStore(text) { store, file in
            #expect(throws: (any Error).self) { try store.apply(.toggle("sleep", from: 0)) }
            #expect(try Data(contentsOf: file) == Data(text.utf8))
            _ = try store.apply(.work("listen"))
            #expect((try json(file)["idle"] as? [[String: Any]])?.first?["pets"] as? [String] == ["future"])
        }
    }

    @Test func cannotRemoveLastPlayablePetEvenWhenUnknownNamesExist() throws {
        try withStore(#"{"idle":[{"from":0,"pets":["sleep","future"]}]}"#) { store, file in
            _ = try store.apply(.toggle("sleep", from: 0))
            #expect((try json(file)["idle"] as? [[String: Any]])?.first?["pets"] as? [String] == ["sleep", "future"])
        }
    }

    @Test func staleMenuSlotDoesNotRecreateRemovedSlot() throws {
        let text = #"{"idle":[{"from":12,"pets":["sleep"]}]}"#
        try withStore(text) { store, file in
            #expect(throws: (any Error).self) { try store.apply(.toggle("listen", from: 0)) }
            let unchanged = try Data(contentsOf: file)
            #expect(unchanged == Data(text.utf8))
        }
    }

    @Test func initialFileCreationDoesNotOverwriteExistingEdits() throws {
        try withStore(nil) { store, file in
            try store.createIfMissing()
            #expect(store.reload() == defaults)
            let text = #"{"work":"listen","new":true}"#
            try Data(text.utf8).write(to: file)
            try store.createIfMissing()
            #expect(try Data(contentsOf: file) == Data(text.utf8))
        }
    }

    @Test func workCanFollowTheTimeSlot() throws {
        try withStore(#"{"work":"slot"}"#) { store, file in
            #expect(store.current.work == Schedule.followSlot)
            _ = try store.apply(.work("listen"))
            #expect(store.current.work == "listen")
            let s = try store.apply(.work(Schedule.followSlot))
            #expect(s.work == Schedule.followSlot)
            #expect(try json(file)["work"] as? String == "slot")
        }
    }

    @Test func editingSymlinkPreservesLinkAndPermissions() throws {
        try withStore(nil) { _, file in
            let target = file.deletingLastPathComponent().appendingPathComponent("dotfile.json")
            try Data(#"{"work":"sleep","keep":true}"#.utf8).write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            let store = ScheduleStore(defaults: defaults, known: ["sleep", "listen"], file: file)
            _ = try store.apply(.work("listen"))
            #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
            #expect(try json(target)["work"] as? String == "listen")
            #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int == 0o600)
        }
    }
}
