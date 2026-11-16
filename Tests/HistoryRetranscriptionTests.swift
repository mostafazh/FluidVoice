import Foundation

@main struct HistoryRetranscriptionTests {
    static func main() throws {
        try self.testDecodesAppWrittenWAV()
        try self.testSkipsUnknownChunksAndDownmixesStereo()
        self.testRejectsUnsupportedAudio()
        self.testCandidateModels()
        self.testDefaultModel()
        print("PASS: history retranscription decoder and model policy")
    }

    /// Mirrors `DictationAudioHistoryStore.wavData(from:)`, the only writer of these files.
    static func wav(
        samples: [Int16],
        sampleRate: Int = 16_000,
        channels: Int = 1,
        audioFormat: UInt16 = 1,
        bitsPerSample: UInt16 = 16,
        extraChunk: (id: String, body: [UInt8])? = nil
    ) -> Data {
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let dataBytes = samples.count * 2
        let extraBytes = extraChunk.map { 8 + $0.body.count + ($0.body.count % 2) } ?? 0
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + extraBytes + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(audioFormat)
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channels * 2))
        append16(UInt16(channels * 2))
        append16(bitsPerSample)
        if let extraChunk {
            data.append(contentsOf: Array(extraChunk.id.utf8))
            append32(UInt32(extraChunk.body.count))
            data.append(contentsOf: extraChunk.body)
            if extraChunk.body.count % 2 == 1 { data.append(0) }
        }
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataBytes))
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func testDecodesAppWrittenWAV() throws {
        let samples = try DictationAudioWAVDecoder.samples(from: self.wav(samples: [0, Int16.max, -Int16.max, 16_384]))
        precondition(samples.count == 4)
        precondition(samples[0] == 0 && samples[1] == 1 && samples[2] == -1)
        precondition(abs(samples[3] - 0.5) < 0.001, "Samples must scale back to [-1, 1]")
    }

    static func testSkipsUnknownChunksAndDownmixesStereo() throws {
        // An odd-sized chunk carries a pad byte; the decoder must step over it.
        let data = self.wav(samples: [1000, 3000, -2000, 2000], channels: 2, extraChunk: ("LIST", [1, 2, 3]))
        let samples = try DictationAudioWAVDecoder.samples(from: data)
        precondition(samples.count == 2, "Stereo frames become one mono sample each")
        precondition(abs(samples[0] - 2000 / Float(Int16.max)) < 0.0001)
        precondition(abs(samples[1]) < 0.0001)
    }

    static func testRejectsUnsupportedAudio() {
        func error(for data: Data) -> DictationAudioWAVDecoder.DecodeError? {
            do {
                _ = try DictationAudioWAVDecoder.samples(from: data)
                return nil
            } catch {
                return error as? DictationAudioWAVDecoder.DecodeError
            }
        }
        precondition(error(for: Data("not audio".utf8)) == .notWAV)
        precondition(error(for: self.wav(samples: [1], sampleRate: 44_100)) == .unsupportedFormat("44100 Hz"))
        precondition(error(for: self.wav(samples: [1], audioFormat: 3, bitsPerSample: 32)) == .unsupportedFormat("format 3, 32-bit"))
        precondition(error(for: self.wav(samples: [])) == .missingAudioData)
        // A truncated header must fail cleanly rather than read past the end.
        precondition(error(for: self.wav(samples: [1, 2]).prefix(30)) != nil)
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
        let otherThanRecorded = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: candidates,
            recordedModelID: "parakeet-tdt",
            selectedModelID: "parakeet-tdt"
        )
        precondition(otherThanRecorded == "whisper-small", "Open on a model other than the one that made the transcript")

        let selected = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: candidates,
            recordedModelID: "whisper-large",
            selectedModelID: "parakeet-tdt"
        )
        precondition(selected == "parakeet-tdt", "Prefer the selected model when it differs from the recorded one")

        let onlyRecorded = HistoryRetranscriptionPolicy.defaultModelID(
            candidates: ["parakeet-tdt"],
            recordedModelID: "parakeet-tdt",
            selectedModelID: "parakeet-tdt"
        )
        precondition(onlyRecorded == "parakeet-tdt", "Fall back to re-running the same model")

        let unknown = HistoryRetranscriptionPolicy.defaultModelID(candidates: candidates, recordedModelID: nil, selectedModelID: nil)
        precondition(unknown == "parakeet-tdt")
        precondition(HistoryRetranscriptionPolicy.defaultModelID(candidates: [], recordedModelID: nil, selectedModelID: "x") == nil)
    }
}
