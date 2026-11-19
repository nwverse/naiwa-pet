import Foundation
import Testing
@testable import naiwa

struct PerPetClipTests {
    func clip(_ name: String, loop: Bool, look: String? = nil, done: String? = nil) -> Assets.Clip {
        Assets.Clip(video: URL(fileURLWithPath: "/nonexistent/\(name).mov"), frames: 24, loop: loop,
                    title: name, desc: "", look: look, done: done)
    }

    var assets: Assets {
        let clips: [String: Assets.Clip] = [
            "immerse": clip("immerse", loop: true, look: "look", done: "glance"),
            "look": clip("look", loop: false),
            "glance": clip("glance", loop: false),
            "relax": clip("relax", loop: true, look: "relax_look", done: "relax_done"),
            "relax_look": clip("relax_look", loop: false),
            "relax_done": clip("relax_done", loop: false),
            "sleep": clip("sleep", loop: true),
            "ghost": clip("ghost", loop: true, look: "missing", done: "missing"),
            "float": clip("float", loop: true, look: "float_look"),
            "float_look": clip("float_look", loop: false),
        ]
        return Assets(fps: 24, clips: clips, pets: ["immerse", "relax", "sleep", "ghost", "float", "look", "glance", "relax_look", "relax_done", "float_look"],
                      defaults: Schedule(idle: [.init(from: 0, pets: ["sleep"])], work: Schedule.followSlot), done: "glance")
    }

    @Test func petsUseTheirOwnLookAndDone() {
        #expect(assets.look(for: "relax") == "relax_look")
        #expect(assets.done(for: "relax") == "relax_done")
        #expect(assets.look(for: "immerse") == "look")
        #expect(assets.done(for: "immerse") == "glance")
    }

    @Test func petsWithoutTheirOwnStayPutWhileWaitingAndBorrowTheDefaultDone() {
        #expect(assets.look(for: "sleep") == "sleep")
        #expect(assets.done(for: "sleep") == "glance")
        #expect(assets.done(for: nil) == "glance")
    }

    @Test func petWithOnlyALookLooksAtYouWhenTouched() {
        #expect(assets.look(for: "float") == "float_look")
        #expect(assets.done(for: "float") == "float_look")
    }

    @Test func missingClipsFallBackInsteadOfBreaking() {
        #expect(assets.look(for: "ghost") == "ghost")
        #expect(assets.done(for: "ghost") == "glance")
    }

    @Test func lookAndDoneClipsBelongToTheirPet() {
        #expect(assets.owner(of: "relax_look") == "relax")
        #expect(assets.owner(of: "relax_done") == "relax")
        #expect(assets.owner(of: "glance") == "immerse")
        #expect(assets.owner(of: "sleep") == "sleep")
        #expect(assets.owner(of: "nope") == nil)
    }

    @Test func onlyLoopingClipsShowUpAsPets() {
        #expect(assets.loopPets == ["immerse", "relax", "sleep", "ghost", "float"])
    }
}

struct WorkPetTests {
    @Test func followingTheSlotKeepsThePetOnStage() {
        #expect(Pet.workCandidate(work: Schedule.followSlot, current: "relax") { _ in true } == "relax")
    }

    @Test func followingTheSlotWithNothingOnStageLetsIdlePick() {
        #expect(Pet.workCandidate(work: Schedule.followSlot, current: nil) { _ in true } == nil)
        #expect(Pet.workCandidate(work: Schedule.followSlot, current: "broken") { $0 != "broken" } == nil)
    }

    @Test func aFixedWorkPetWins() {
        #expect(Pet.workCandidate(work: "immerse", current: "relax") { _ in true } == "immerse")
    }

    @Test func finishingATurnFreesThePetButIdleTouchesDoNot() {
        #expect(Pet.keptPet("relax", mood: .idle, lastMood: .working) == nil)
        #expect(Pet.keptPet("relax", mood: .idle, lastMood: .waiting) == nil)
        #expect(Pet.keptPet("relax", mood: .idle, lastMood: .idle) == "relax")
        #expect(Pet.keptPet("relax", mood: .working, lastMood: .idle) == "relax")
        #expect(Pet.keptPet("relax", mood: .waiting, lastMood: .working) == "relax")
    }
}
