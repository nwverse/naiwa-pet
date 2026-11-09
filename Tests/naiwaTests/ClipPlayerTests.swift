import Foundation
import Testing
@testable import naiwa

/// 片段打不开（文件不在、坏了）也要回报结束，不然奶蛙会卡在「做完」里。
/// 回调走主队列：测试本身不能占着主线程，在别的线程上等
@Suite struct ClipPlayerTests {
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var player: ClipPlayer?
        var ended: Bool { lock.withLock { done } }
        func end() { lock.withLock { done = true } }
    }

    /// 在临时目录里放一个 clip.mov（nil 就不放），用真的 ClipPlayer 播，最多等 `wait` 秒，返回回调来没来
    func ends(_ bytes: Data?, wait: Double = 5) async throws -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("naiwa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("clip.mov")
        if let bytes { try bytes.write(to: url) }
        let box = Box()
        await MainActor.run {
            box.player = ClipPlayer(Assets.Clip(video: url, frames: 72, loop: false, title: "", desc: ""), fps: 24)
            box.player?.play { box.end() }
        }
        for _ in 0..<Int(wait * 20) where !box.ended { try await Task.sleep(nanoseconds: 50_000_000) }
        await MainActor.run { box.player = nil }
        return box.ended
    }

    @Test func missingFileEnds() async throws {
        #expect(try await ends(nil))
    }

    @Test func garbageFileEnds() async throws {
        #expect(try await ends(Data((0..<200_000).map { _ in UInt8.random(in: 0...255) })))
    }
}
