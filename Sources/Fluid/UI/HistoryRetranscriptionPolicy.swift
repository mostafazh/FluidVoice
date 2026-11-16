import Foundation

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
        currentModelID: String?,
        selectedModelID: String?
    ) -> String? {
        let others = candidates.filter { $0 != currentModelID }
        if let selectedModelID, others.contains(selectedModelID) { return selectedModelID }
        return others.first ?? candidates.first
    }
}
