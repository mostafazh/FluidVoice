@testable import FluidVoice_Debug
import XCTest

/// Runs `ASRService.retranscribeSavedAudio` against an injected provider: no model files,
/// no CoreML. Covers the lease, the install check and padding; not real inference.
@MainActor
final class HistoryRetranscriptionASRTests: XCTestCase {
    private final class FakeProvider: TranscriptionProvider {
        let name = "Retranscription test provider"
        let isAvailable = true
        var isReady = false
        var installed = true
        private(set) var prepareCount = 0
        private(set) var inputs: [[Float]] = []

        func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
            self.prepareCount += 1
            self.isReady = true
        }

        func modelsExistOnDisk() -> Bool {
            self.installed
        }

        func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
            self.inputs.append(samples)
            return ASRTranscriptionResult(text: "hello there", confidence: 0.9)
        }
    }

    /// The model under test must not be the selected one, so the isolated-provider path runs.
    private func selectWhisperBase() -> SettingsStore.SpeechModel {
        let original = SettingsStore.shared.selectedSpeechModel
        SettingsStore.shared.selectedSpeechModel = .whisperBase
        return original
    }

    private func makeService(provider: FakeProvider) -> ASRService {
        let asr = ASRService(meetingModelResidency: MeetingModelResidencyCoordinator())
        asr.modelProvidersForTesting[.whisperTiny] = provider
        return asr
    }

    func testOtherModelIsPreparedPaddedAndReleasesTheLease() async throws {
        let originalModel = self.selectWhisperBase()
        defer { SettingsStore.shared.selectedSpeechModel = originalModel }
        let provider = FakeProvider()
        let asr = self.makeService(provider: provider)
        let result = try await asr.retranscribeSavedAudio(Array(repeating: 0.25, count: 8000), with: .whisperTiny)
        await asr.shutdownForTermination()

        XCTAssertEqual(provider.prepareCount, 1)
        let input = try XCTUnwrap(provider.inputs.first)
        XCTAssertEqual(input.count, 16_000, "Input shorter than one second is padded with silence")
        XCTAssertEqual(Array(input.dropFirst(8000)), Array(repeating: 0, count: 8000))
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("hello"))
        XCTAssertNil(asr.activeExclusiveActivity, "The lease is released when the call returns")
        XCTAssertEqual(SettingsStore.shared.selectedSpeechModel, .whisperBase, "The selected model never changes")
    }

    func testMissingModelIsRefusedBeforePreparing() async {
        let originalModel = self.selectWhisperBase()
        defer { SettingsStore.shared.selectedSpeechModel = originalModel }
        let provider = FakeProvider()
        provider.installed = false
        let asr = self.makeService(provider: provider)
        do {
            _ = try await asr.retranscribeSavedAudio([0.1], with: .whisperTiny)
            XCTFail("A model without files must be refused")
        } catch {
            XCTAssertEqual(error as? HistoryRetranscriptionError, .modelNotInstalled(SettingsStore.SpeechModel.whisperTiny.displayName))
        }
        await asr.shutdownForTermination()
        XCTAssertEqual(provider.prepareCount, 0, "Preparing would download the missing files")
        XCTAssertNil(asr.activeExclusiveActivity)
    }

    func testAnotherActivityKeepsItsLease() async throws {
        let originalModel = self.selectWhisperBase()
        defer { SettingsStore.shared.selectedSpeechModel = originalModel }
        let provider = FakeProvider()
        let asr = self.makeService(provider: provider)
        let dictation = try asr.acquireExclusiveActivity(.dictation)
        do {
            _ = try await asr.retranscribeSavedAudio([0.1], with: .whisperTiny)
            XCTFail("Retranscription must not overlap dictation")
        } catch {
            guard case let ASRActivityError.activityInProgress(activity) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(activity, .dictation)
        }
        XCTAssertEqual(asr.activeExclusiveActivity, .dictation)
        XCTAssertTrue(provider.inputs.isEmpty)
        asr.releaseExclusiveActivity(dictation)
        await asr.shutdownForTermination()
    }

    func testEmptyAudioIsRefusedAndReleasesTheLease() async {
        let originalModel = self.selectWhisperBase()
        defer { SettingsStore.shared.selectedSpeechModel = originalModel }
        let provider = FakeProvider()
        let asr = self.makeService(provider: provider)
        do {
            _ = try await asr.retranscribeSavedAudio([], with: .whisperTiny)
            XCTFail("Empty audio must be refused")
        } catch {
            XCTAssertEqual(error as? HistoryRetranscriptionError, .emptyAudio)
        }
        await asr.shutdownForTermination()
        XCTAssertEqual(provider.prepareCount, 0)
        XCTAssertNil(asr.activeExclusiveActivity)
    }
}
