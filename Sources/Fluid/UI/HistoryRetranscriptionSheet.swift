import AppKit
import SwiftUI

/// Runs a saved dictation recording through another installed voice model, shows
/// the new transcript next to the current one, and lets the person keep it.
struct HistoryRetranscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @ObservedObject private var installations = SpeechModelInstallationSnapshot.shared

    let entry: TranscriptionHistoryEntry
    /// Saves the new transcript. Returns false when the entry no longer exists.
    let onReplace: (_ text: String, _ model: SettingsStore.SpeechModel) -> Bool

    private enum Phase: Equatable {
        case choosing
        case running(SettingsStore.SpeechModel)
        case finished(text: String, model: SettingsStore.SpeechModel, durationMilliseconds: Int)
    }

    @State private var selectedModelID: String?
    @State private var phase: Phase = .choosing
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Retranscribe recording")
                    .font(.fluidSystem(size: 18, weight: .semibold))
                Text("Run this recording through another voice model. Your selected model stays the same.")
                    .font(.fluidSystem(size: 12))
                    .foregroundStyle(.secondary)
            }

            self.modelPicker

            switch self.phase {
            case .choosing:
                EmptyView()
            case let .running(model):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).fixedSize()
                    Text("Loading \(model.displayName) and transcribing…")
                        .font(.fluidSystem(size: 12))
                        .foregroundStyle(.secondary)
                }
            case let .finished(text, model, durationMilliseconds):
                self.transcriptField(
                    title: "New · \(model.displayName) · \(TranscriptionHistoryEntry.formattedDuration(milliseconds: durationMilliseconds))",
                    text: text
                )
                self.transcriptField(title: "Current", text: self.entry.clipboardText ?? "")
                Text(self.replaceNote)
                    .font(.fluidSystem(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.fluidSystem(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            self.actions
        }
        .padding(20)
        .frame(width: 560)
        .background(self.theme.palette.contentBackground)
        .onAppear {
            if self.installations.state != .ready { self.installations.refresh() }
            self.applyDefaultSelectionIfNeeded()
        }
        .onChange(of: self.candidateModels.map(\.id)) { _, _ in
            self.applyDefaultSelectionIfNeeded()
        }
        // A model run cannot be interrupted and holds the ASR lease until it ends,
        // so the sheet stays open and shows that state instead of hiding it.
        .interactiveDismissDisabled(self.isRunning)
    }

    // MARK: - Sections

    @ViewBuilder
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current = self.currentModel {
                Text("Current transcript from \(current.displayName)")
                    .font(.fluidSystem(size: 11))
                    .foregroundStyle(.secondary)
            }
            if self.candidateModels.isEmpty {
                Text(self.installations.isChecking ? "Checking downloaded models…" : "No downloaded voice models are available.")
                    .font(.fluidSystem(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Voice model", selection: self.$selectedModelID) {
                    ForEach(self.candidateModels) { model in
                        Text(self.pickerLabel(for: model)).tag(Optional(model.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(self.isRunning)
                .onChange(of: self.selectedModelID) { _, _ in
                    if case .finished = self.phase { self.phase = .choosing }
                    self.errorMessage = nil
                }
                if self.selectedModel == .appleSpeech {
                    Text("Apple Speech may send this recording to Apple's servers, as it does when you dictate with it.")
                        .font(.fluidSystem(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            if case let .finished(text, _, _) = self.phase {
                Button("Copy") { self.copy(text) }
            }
            Spacer()
            Button("Close") { self.dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(self.isRunning)

            if case let .finished(text, model, _) = self.phase {
                Button("Replace transcript") {
                    if self.onReplace(text, model) {
                        self.dismiss()
                    } else {
                        self.errorMessage = HistoryRetranscriptionError.entryMissing.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Retranscribe") { self.start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isRunning || self.selectedModel == nil)
            }
        }
    }

    private func transcriptField(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.fluidSystem(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ScrollView {
                Text(text)
                    .font(.fluidSystem(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(height: 96)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(self.theme.palette.cardBorder.opacity(0.55), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Models

    private var candidateModels: [SettingsStore.SpeechModel] {
        let ids = HistoryRetranscriptionPolicy.candidateModelIDs(
            availableIDs: SettingsStore.SpeechModel.availableModels.map(\.id),
            installedIDs: self.installations.installedIDs
        )
        return ids.compactMap { SettingsStore.SpeechModel(rawValue: $0) }
    }

    /// The model that produced the entry's current transcript (`audio.model`).
    private var currentModel: SettingsStore.SpeechModel? {
        self.entry.audio?.model.flatMap { SettingsStore.SpeechModel(rawValue: $0) }
    }

    private var replaceNote: String {
        let permanence = "Replacing can't be undone."
        return self.entry.wasAIProcessed
            ? "\(permanence) It saves the new transcript without AI cleanup, so the AI-cleaned text shown under Current is lost."
            : permanence
    }

    private var selectedModel: SettingsStore.SpeechModel? {
        self.selectedModelID.flatMap { id in self.candidateModels.first { $0.id == id } }
    }

    private var isRunning: Bool {
        if case .running = self.phase { return true }
        return false
    }

    private func pickerLabel(for model: SettingsStore.SpeechModel) -> String {
        var label = model.displayName
        if model == self.currentModel { label += " (current transcript)" }
        if model == SettingsStore.shared.selectedSpeechModel { label += " (selected)" }
        return label
    }

    private func applyDefaultSelectionIfNeeded() {
        let ids = self.candidateModels.map(\.id)
        if let current = self.selectedModelID, ids.contains(current) { return }
        self.selectedModelID = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: ids,
            currentModelID: self.entry.audio?.model,
            selectedModelID: SettingsStore.shared.selectedSpeechModel.id
        )
    }

    // MARK: - Actions

    private func start() {
        guard let model = self.selectedModel, !self.isRunning else { return }
        self.errorMessage = nil
        self.phase = .running(model)
        let entry = self.entry
        // Not cancellable by design: the sheet waits for the run, so every outcome,
        // including an unexpected cancellation, ends back in `choosing` or `finished`.
        Task { @MainActor in
            // Wall time for this sheet only (decode, load and inference); it is not saved.
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                let samples = try await Task.detached(priority: .userInitiated) {
                    try DictationAudioHistoryStore.shared.loadSamples(for: entry)
                }.value
                let result = try await AppServices.shared.asr.retranscribeSavedAudio(samples, with: model)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw HistoryRetranscriptionError.emptyTranscript(model.displayName) }
                let duration = Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded())
                self.phase = .finished(text: text, model: model, durationMilliseconds: duration)
            } catch {
                DebugLogger.shared.error(
                    "History retranscription failed: \(error.localizedDescription)",
                    source: "HistoryRetranscriptionSheet"
                )
                self.errorMessage = error is CancellationError
                    ? "Retranscription was interrupted. Try again."
                    : error.localizedDescription
                self.phase = .choosing
            }
        }
    }

    private func copy(_ text: String) {
        ClipboardAudit.record("ui_copy_begin")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardAudit.record("ui_copy_end")
    }
}
