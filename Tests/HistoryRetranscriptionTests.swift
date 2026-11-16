import Foundation

@main struct HistoryRetranscriptionTests {
    static func main() {
        self.testCandidateModels()
        self.testDefaultModel()
        print("PASS: history retranscription model policy")
    }

    static func testCandidateModels() {
        let candidates = HistoryRetranscriptionPolicy.candidateModelIDs(
            availableIDs: ["parakeet-tdt", "whisper-small", "apple-speech", "whisper-large", "whisper-small"],
            installedIDs: ["whisper-large", "parakeet-tdt", "whisper-small", "not-listed"]
        )
        precondition(candidates == ["parakeet-tdt", "whisper-small", "whisper-large"], "Installed models only, in app order, once each")
        precondition(HistoryRetranscriptionPolicy.candidateModelIDs(availableIDs: ["a"], installedIDs: []).isEmpty)
    }

    static func testDefaultModel() {
        let candidates = ["parakeet-tdt", "whisper-small", "whisper-large"]
        let otherThanCurrent = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: candidates,
            currentModelID: "parakeet-tdt",
            selectedModelID: "parakeet-tdt"
        )
        precondition(otherThanCurrent == "whisper-small", "Open on a model other than the one that made the transcript")

        let selected = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: candidates,
            currentModelID: "whisper-large",
            selectedModelID: "parakeet-tdt"
        )
        precondition(selected == "parakeet-tdt", "Prefer the selected model when it differs from the current one")

        let onlyCurrent = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: ["parakeet-tdt"],
            currentModelID: "parakeet-tdt",
            selectedModelID: "parakeet-tdt"
        )
        precondition(onlyCurrent == "parakeet-tdt", "Fall back to re-running the same model")

        let unknown = HistoryRetranscriptionPolicy.defaultModelID(candidates: candidates, currentModelID: nil, selectedModelID: nil)
        precondition(unknown == "parakeet-tdt")
        precondition(HistoryRetranscriptionPolicy.defaultModelID(candidates: [], currentModelID: nil, selectedModelID: "x") == nil)
    }
}
