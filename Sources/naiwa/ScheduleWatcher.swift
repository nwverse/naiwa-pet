import Foundation

/// 同时看文件和父目录：既能收到原地写入，也能收到编辑器的原子替换、删除和重建。
/// 没有周期定时器，配置目录尚不存在时监听最近的已有父目录。
final class ScheduleWatcher {
    private struct Watch {
        let identity: String
        let source: DispatchSourceFileSystemObject
    }
    private let file: URL
    private let changed: () -> Void
    private var watches: [URL: Watch] = [:]
    private var pending: DispatchWorkItem?

    init(file: URL = Schedule.file, changed: @escaping () -> Void) {
        self.file = file
        self.changed = changed
        refresh()
    }

    deinit {
        pending?.cancel()
        watches.values.forEach { $0.source.cancel() }
    }

    private func refresh() {
        var paths: Set<URL> = [file, file.resolvingSymlinksInPath()]
        for leaf in Array(paths) {
            var parent = leaf.deletingLastPathComponent()
            paths.insert(parent)
            // 监听目录本身被删掉后的重建；父目录也不存在则继续向上找。
            repeat {
                let next = parent.deletingLastPathComponent()
                guard next != parent else { break }
                parent = next
                paths.insert(parent)
            } while !FileManager.default.fileExists(atPath: parent.path)
        }
        for path in Array(watches.keys) where !paths.contains(path) {
            watches.removeValue(forKey: path)?.source.cancel()
        }
        for path in paths {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
            let identity = attrs.flatMap { a -> String? in
                guard let device = a[.systemNumber], let inode = a[.systemFileNumber] else { return nil }
                return "\(device):\(inode)"
            }
            if watches[path]?.identity == identity { continue }
            watches.removeValue(forKey: path)?.source.cancel()
            guard let identity else { continue }
            let fd = open(path.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib, .revoke], queue: .main)
            source.setCancelHandler { close(fd) }
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            watches[path] = Watch(identity: identity, source: source)
            source.resume()
        }
    }

    private func scheduleReload() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refresh()
            self.changed()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
}
