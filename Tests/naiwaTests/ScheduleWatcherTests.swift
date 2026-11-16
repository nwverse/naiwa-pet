import Foundation
import Testing
@testable import naiwa

@MainActor struct ScheduleWatcherTests {
    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<120 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition())
    }

    @Test func watchesCreationAtomicReplacementInPlaceWriteAndDirectoryRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("config/naiwa")
        let file = dir.appendingPathComponent("config.json")
        let defaults = Schedule(idle: [.init(from: 0, pets: ["sleep"])], work: "sleep")
        let store = ScheduleStore(defaults: defaults, known: ["sleep", "listen"], file: file)
        let watcher = ScheduleWatcher(file: file) { store.reload() }
        defer { withExtendedLifetime(watcher) {} }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"work":"listen"}"#.utf8).write(to: file, options: .atomic)
        try await waitFor { store.current.work == "listen" }
        try Data(#"{"work":"sleep"}"#.utf8).write(to: file, options: .atomic)
        try await waitFor { store.current.work == "sleep" }

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(#"{"work":"listen"}"#.utf8))
        try handle.close()
        try await waitFor { store.current.work == "listen" }

        try FileManager.default.removeItem(at: dir)
        try await waitFor { store.current.work == "sleep" }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"work":"listen"}"#.utf8).write(to: file, options: .atomic)
        try await waitFor { store.current.work == "listen" }
    }
}
