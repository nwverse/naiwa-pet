import AVFoundation
import Testing
@testable import naiwa

private final class ControlledPlayer: AVPlayer {
    var completions: [(Bool) -> Void] = []
    var plays = 0
    var pauses = 0

    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                       completionHandler: @escaping (Bool) -> Void) {
        completions.append(completionHandler)
    }
    override func play() { plays += 1; #expect(Thread.isMainThread) }
    override func pause() { pauses += 1 }
}

struct ClipPlayerTests {
    @MainActor private func makeClip(_ player: ControlledPlayer) -> ClipPlayer {
        let clip = Assets.Clip(video: URL(fileURLWithPath: "/nonexistent/test.mov"), frames: 24,
                               loop: false, title: "Test", desc: "")
        return ClipPlayer(clip, fps: 24, player: player)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test @MainActor func testSuccessfulCurrentSeekPlaysOnMainQueue() async {
        let player = ControlledPlayer()
        let clip = makeClip(player)
        clip.play(onEnd: {})
        let completion = player.completions[0]
        await Task.detached { completion(true) }.value
        await drainMainQueue()
        #expect(player.plays == 1)
        clip.stop()
    }

    @Test @MainActor func testCancelledSeekDoesNotPlay() async {
        let player = ControlledPlayer()
        let clip = makeClip(player)
        clip.play(onEnd: {})
        player.completions[0](false)
        await drainMainQueue()
        #expect(player.plays == 0)
        clip.stop()
    }

    @Test @MainActor func testLateSeekAfterStopDoesNotPlay() async {
        let player = ControlledPlayer()
        let clip = makeClip(player)
        clip.play(onEnd: {})
        clip.stop()
        player.completions[0](true)
        await drainMainQueue()
        #expect(player.plays == 0)
        #expect(player.pauses == 1)
    }

    @Test @MainActor func testStopInvalidatesCompletionAlreadyQueuedOnMain() async {
        let player = ControlledPlayer()
        let clip = makeClip(player)
        clip.play(onEnd: {})
        player.completions[0](true)
        clip.stop()
        await drainMainQueue()
        #expect(player.plays == 0)
    }

    @Test @MainActor func testRestartIgnoresOldSeekAndPlaysCurrentSeek() async {
        let player = ControlledPlayer()
        let clip = makeClip(player)
        clip.play(onEnd: {})
        clip.play(onEnd: {})
        player.completions[0](true)
        await drainMainQueue()
        #expect(player.plays == 0)
        player.completions[1](true)
        await drainMainQueue()
        #expect(player.plays == 1)
        clip.stop()
    }

    @Test @MainActor func testDeinitPausesAndLateSeekDoesNotRetainPlayerOwner() async {
        let player = ControlledPlayer()
        var clip: ClipPlayer? = makeClip(player)
        weak var weakClip = clip
        clip?.play(onEnd: {})
        clip = nil
        #expect(weakClip == nil)
        #expect(player.pauses == 1)
        player.completions[0](true)
        await drainMainQueue()
        #expect(player.plays == 0)
    }
}
