import Foundation

/// Failures of `ASRService.retranscribeSavedAudio(_:with:)` and the History sheet that calls it.
nonisolated enum HistoryRetranscriptionError: LocalizedError, Equatable {
    case emptyAudio
    case modelNotInstalled(String)
    case modelMaintenanceInProgress
    case emptyTranscript(String)
    case entryMissing

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "This recording has no audio to transcribe."
        case let .modelNotInstalled(model):
            return "\(model) is not downloaded. Download it in Voice Engine settings, then try again."
        case .modelMaintenanceInProgress:
            return "Wait for the voice model download or deletion to finish, then try again."
        case let .emptyTranscript(model):
            return "\(model) did not hear any speech in this recording."
        case .entryMissing:
            return "This dictation was deleted, so its transcript could not be replaced."
        }
    }
}
