import Testing
@testable import naiwa

struct IdleFallbackTests {
    @Test func brokenHoverSelectionFallsBackToHealthySlot() {
        var turn = 0
        #expect(Pet.idleCandidate(picked: "bad", shown: "bad", names: ["bad", "healthy"],
                                  broken: ["bad"], turn: &turn) == "healthy")
    }

    @Test func brokenCandidatesAreSkippedAcrossRepeatedSelections() {
        var turn = 0
        for _ in 0..<5 {
            #expect(Pet.idleCandidate(picked: nil, shown: nil, names: ["bad", "healthy"],
                                      broken: ["bad"], turn: &turn) == "healthy")
        }
    }

    @Test func allBrokenCandidatesStopPlayback() {
        var turn = 0
        #expect(Pet.idleCandidate(picked: "bad", shown: "bad", names: ["bad"],
                                  broken: ["bad"], turn: &turn) == nil)
    }
}
