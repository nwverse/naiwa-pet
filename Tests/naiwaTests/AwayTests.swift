import AppKit
import Testing
@testable import naiwa

struct AwayTests {
    static let sleep = NSWorkspace.screensDidSleepNotification, wake = NSWorkspace.screensDidWakeNotification
    static let resign = NSWorkspace.sessionDidResignActiveNotification, active = NSWorkspace.sessionDidBecomeActiveNotification
    static let lock = Notification.Name("com.apple.screenIsLocked"), unlock = Notification.Name("com.apple.screenIsUnlocked")

    // #9：屏幕睡着 → 锁屏 → 屏幕醒来（还在锁屏界面），不能接着播
    @Test func wakeOnLockScreenStaysAway() {
        var a = Away()
        a.apply(Self.sleep, lockedNow: false)
        a.apply(Self.lock, lockedNow: true)
        a.apply(Self.wake, lockedNow: true)
        #expect(a.any)
        a.apply(Self.unlock, lockedNow: false)
        #expect(!a.any)
    }

    // 解锁通知比醒来先到（或者没来）：醒来时按当时查到的锁屏状态算
    @Test func wakeRechecksLock() {
        var a = Away()
        a.apply(Self.sleep, lockedNow: false)
        a.apply(Self.lock, lockedNow: true)
        a.apply(Self.wake, lockedNow: false)
        #expect(!a.any)
    }

    // 锁屏期间醒来又睡下：锁屏那一项不跟着屏幕走
    @Test func lockSurvivesSleepAndWake() {
        var a = Away()
        a.apply(Self.lock, lockedNow: true)
        a.apply(Self.sleep, lockedNow: true)
        a.apply(Self.wake, lockedNow: true)
        #expect(a.any && a.locked && !a.asleep)
    }

    // 切到别的用户再切回来：锁着就还算离开
    @Test func becomeActiveRechecksLock() {
        var a = Away()
        a.apply(Self.resign, lockedNow: false)
        #expect(a.any)
        a.apply(Self.active, lockedNow: true)
        #expect(a.any && !a.inactive)
        a.apply(Self.unlock, lockedNow: false)
        #expect(!a.any)
    }
}
