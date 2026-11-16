import Foundation

nonisolated enum HistoryRetranscriptionError: LocalizedError, Equatable {
    case emptyAudio
    case modelNotInstalled(String)
    case emptyTranscript(String)

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "This recording has no audio to transcribe."
        case let .modelNotInstalled(model):
            return "\(model) is not downloaded. Download it in Voice Engine settings, then try again."
        case let .emptyTranscript(model):
            return "\(model) did not hear any speech in this recording."
        }
    }
}

/// Which voice models a saved recording can be retranscribed with. Works on model
/// IDs only, so the rules stay free of settings, providers and disk access.
nonisolated enum HistoryRetranscriptionPolicy {
    /// Installed models, in the order the app lists them.
    static func candidateModelIDs(availableIDs: [String], installedIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        return availableIDs.filter { installedIDs.contains($0) && seen.insert($0).inserted }
    }

    /// Prefer a model other than the one that made the current transcript, then the
    /// selected model, so the sheet opens on a useful comparison.
    static func defaultModelID(
        candidates: [String],
        recordedModelID: String?,
        selectedModelID: String?
    ) -> String? {
        let others = candidates.filter { $0 != recordedModelID }
        if let selectedModelID, others.contains(selectedModelID) { return selectedModelID }
        return others.first ?? candidates.first
    }
}
