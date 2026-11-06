import AppKit
import CoreVideo
import Testing
@testable import naiwa

/// 指针停着不动、画面换了形状：窗口接不接鼠标要跟着当前帧变（#25）
@MainActor
struct PassThroughTests {
    /// IOSurface 做底的 BGRA 帧，中心一块的透明度是 centerAlpha，其余全透明
    func frame(centerAlpha: UInt8, size: Int = 64) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, attrs, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        let base = CVPixelBufferGetBaseAddress(buf)!, row = CVPixelBufferGetBytesPerRow(buf)
        for y in 0..<size {
            for x in 0..<size {
                let center = abs(x - size / 2) < size / 4 && abs(y - size / 2) < size / 4
                base.storeBytes(of: center ? centerAlpha : 0, toByteOffset: y * row + x * 4 + 3, as: UInt8.self)
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    func make(pointer: NSPoint) -> (PetPanel, PetView) {
        _ = NSApplication.shared
        let panel = PetPanel(size: 100)
        panel.setFrameOrigin(NSPoint(x: 200, y: 200))
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.mouseLocation = { pointer }
        panel.contentView = view
        return (panel, view)
    }

    @Test func followsFrameWhenPointerInside() {
        let (panel, view) = make(pointer: NSPoint(x: 250, y: 250))
        view.show(frame(centerAlpha: 255))
        #expect(panel.ignoresMouseEvents == false)
        view.show(frame(centerAlpha: 0))
        #expect(panel.ignoresMouseEvents == true)
        view.show(frame(centerAlpha: 255))
        #expect(panel.ignoresMouseEvents == false)
    }

    @Test func untouchedWhenPointerOutside() {
        let (panel, view) = make(pointer: NSPoint(x: 50, y: 50))
        panel.ignoresMouseEvents = false
        view.show(frame(centerAlpha: 0))
        #expect(panel.ignoresMouseEvents == false)
    }
}
