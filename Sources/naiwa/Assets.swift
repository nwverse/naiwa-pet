import AppKit
import AVFoundation

/// 素材目录：
///   assets.json  {"fps": 24,
///                 "pets": ["sleep", "listen", …],
///                 "clips": {"relax": {"video": "relax.mov", "frames": 109, "loop": true, "title": "悠闲", "desc": "…",
///                                     "look": "relax_look", "done": "relax_glance"},
///                           "relax_look": {"video": "relax_look.mov", "frames": 60, "loop": false, …}, …},
///                 "idle": [{"from": 12, "pets": ["listen", "relax"]}, …],
///                 "work": "slot", "done": "glance"}
///   *.mov        带透明通道的 HEVC（预乘透明度）
///   pets         有哪几只（菜单里的顺序）；循环的那些空闲、干活都能用
///   idle / work  默认的安排，用户可以在 ~/.config/naiwa/config.json 里换（见 Schedule）
///   clip 的 look / done  这只自己的等你（播完停在最后一帧，一直看着你）/ 做完、点它（瞥你一眼）
///   done         没有自己「做完」片段的奶蛙用这段
struct Assets {
    struct Clip {
        let video: URL
        let frames: Int
        let loop: Bool
        let title: String
        let desc: String
        var look: String? = nil
        var done: String? = nil
    }

    let fps: Double
    let clips: [String: Clip]
    let pets: [String]
    let defaults: Schedule
    let done: String

    /// 能拿来空闲、干活的（循环的）那几只
    var loopPets: [String] { pets.filter { clips[$0]?.loop == true } }

    func title(_ name: String) -> String { clips[name]?.title ?? name }

    /// 这只等你时演哪段：有自己的「看着你」就用；没有就还是它自己，只冒气泡（不换成别的奶蛙）
    func look(for pet: String) -> String {
        clips[pet]?.look.flatMap { clips[$0] != nil ? $0 : nil } ?? pet
    }

    /// 这只做完、被点被摸时演哪段：有自己的就用；没有但有「看着你」，就睁眼看你一下再回去；都没有才用默认的那段
    func done(for pet: String?) -> String {
        guard let pet, let c = clips[pet] else { return done }
        return [c.done, c.look].compactMap { $0 }.first { clips[$0] != nil } ?? done
    }

    /// 片段是哪只的：look / done 片段算到它那只上，循环的就是它自己
    func owner(of clip: String) -> String? {
        if clips[clip]?.loop == true { return clip }
        return loopPets.first { clips[$0]?.look == clip || clips[$0]?.done == clip }
    }

    static func load() -> Assets? {
        for dir in candidates() {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("assets.json")),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = j["clips"] as? [String: [String: Any]] else { continue }
            var clips: [String: Clip] = [:]
            for (name, c) in list {
                guard let video = c["video"] as? String else { continue }
                clips[name] = Clip(video: dir.appendingPathComponent(video), frames: c["frames"] as? Int ?? 0, loop: c["loop"] as? Bool ?? false,
                                   title: c["title"] as? String ?? name, desc: c["desc"] as? String ?? "",
                                   look: c["look"] as? String, done: c["done"] as? String)
            }
            let pets = (j["pets"] as? [String] ?? clips.keys.sorted()).filter { clips[$0] != nil }
            let defaults = Schedule(json: j, known: Set(clips.keys))
            let done = j["done"] as? String ?? ""
            guard let defaults, clips[done] != nil else { continue }
            return Assets(fps: j["fps"] as? Double ?? 24, clips: clips, pets: pets, defaults: defaults, done: done)
        }
        return nil
    }

    /// NAIWA_ASSETS → Naiwa.app/Contents/Resources/assets → 可执行文件旁边的 ../Resources/assets → 往上找仓库里的 assets/
    private static func candidates() -> [URL] {
        var out: [URL] = []
        if let env = ProcessInfo.processInfo.environment["NAIWA_ASSETS"] {
            out.append(URL(fileURLWithPath: env))
        }
        if let res = Bundle.main.resourceURL {
            out.append(res.appendingPathComponent("assets"))
        }
        var dir = CLI.executable().deletingLastPathComponent()
        // 经过 ~/.local/bin/naiwa 软链跑的时候 Bundle.main 认不出 App，按可执行文件的位置找 Contents/Resources/assets
        out.append(dir.deletingLastPathComponent().appendingPathComponent("Resources/assets"))
        for _ in 0..<5 {
            out.append(dir.appendingPathComponent("assets"))
            dir.deleteLastPathComponent()
        }
        return out
    }
}

/// 一段片段的播放器：系统硬件解码视频，播放时按帧取出像素缓冲。
/// 缓冲是 IOSurface 做底的，直接交给图层显示，不复制、不上传（复制成 CGImage 再贴，空闲循环要多占 8% 左右的 CPU）。
final class ClipPlayer {
    let duration: Double
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ])
    private var playGeneration = 0
    private var onEnd: (() -> Void)?
    private var endObservers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?
    /// 打不开（文件不在、坏了）：这时也回报结束，不然等不到头
    var failed: Bool { item.status == .failed }

    init(_ clip: Assets.Clip, fps: Double, player: AVPlayer? = nil) {
        duration = Double(clip.frames) / fps
        item = AVPlayerItem(url: clip.video)
        item.add(output)
        self.player = player ?? AVPlayer(playerItem: item)
        self.player.actionAtItemEnd = .pause
        self.player.isMuted = true
        self.player.preventsDisplaySleepDuringVideoPlayback = false
        endObservers = [.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime].map {
            NotificationCenter.default.addObserver(forName: $0, object: item, queue: .main) { [weak self] _ in self?.finish() }
        }
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.finish() }
        }
    }

    deinit {
        playGeneration += 1
        player.pause()
        endObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func play(onEnd: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        playGeneration += 1
        let gen = playGeneration
        self.onEnd = onEnd
        if failed {
            return DispatchQueue.main.async { [weak self] in
                guard let self, self.playGeneration == gen else { return }
                self.finish()
            }
        }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            // 与 play / stop 串行；回调到达后、主队列执行前的 stop 也必须让它失效。
            DispatchQueue.main.async { [weak self] in
                guard let self = self, finished, self.playGeneration == gen else { return }
                self.player.play()
            }
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        playGeneration += 1
        onEnd = nil
        player.pause()
    }

    private func finish() {
        let done = onEnd
        stop()
        done?()
    }

    /// 当前该显示的新帧（BGRA、预乘透明度、IOSurface 做底）；没有新帧返回 nil
    func nextFrame() -> CVPixelBuffer? {
        let t = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: t) else { return nil }
        return output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil)
    }
}
