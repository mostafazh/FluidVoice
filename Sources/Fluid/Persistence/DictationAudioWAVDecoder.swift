import Foundation

/// Reads back the 16-bit PCM WAV files that `DictationAudioHistoryStore` writes,
/// so a saved dictation can be run through a speech model again.
nonisolated enum DictationAudioWAVDecoder {
    enum DecodeError: LocalizedError, Equatable {
        case notWAV
        case unsupportedFormat(String)
        case missingAudioData

        var errorDescription: String? {
            switch self {
            case .notWAV:
                return "Saved audio is not a WAV file."
            case let .unsupportedFormat(detail):
                return "Saved audio uses an unsupported format (\(detail))."
            case .missingAudioData:
                return "Saved audio has no sound data."
            }
        }
    }

    /// Speech models take 16 kHz mono samples.
    static let requiredSampleRate = 16_000

    /// Decodes the file at `url` into 16 kHz mono float samples in [-1, 1].
    static func samples(contentsOf url: URL) throws -> [Float] {
        try self.samples(from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Decodes WAV bytes into 16 kHz mono float samples in [-1, 1].
    /// Multi-channel audio is averaged down to mono.
    static func samples(from data: Data) throws -> [Float] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              Self.fourCC(bytes, at: 0) == "RIFF",
              Self.fourCC(bytes, at: 8) == "WAVE"
        else {
            throw DecodeError.notWAV
        }

        var format: (audioFormat: Int, channels: Int, sampleRate: Int, bitsPerSample: Int)?
        var dataRange: Range<Int>?
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkID = Self.fourCC(bytes, at: offset)
            let chunkSize = Int(Self.uint32LE(bytes, at: offset + 4))
            let bodyStart = offset + 8
            let bodyEnd = min(bodyStart + chunkSize, bytes.count)

            if chunkID == "fmt ", bodyEnd - bodyStart >= 16 {
                format = (
                    audioFormat: Int(Self.uint16LE(bytes, at: bodyStart)),
                    channels: Int(Self.uint16LE(bytes, at: bodyStart + 2)),
                    sampleRate: Int(Self.uint32LE(bytes, at: bodyStart + 4)),
                    bitsPerSample: Int(Self.uint16LE(bytes, at: bodyStart + 14))
                )
            } else if chunkID == "data" {
                dataRange = bodyStart..<bodyEnd
            }

            // Chunks are word-aligned: an odd-sized chunk carries one pad byte.
            offset = bodyStart + chunkSize + (chunkSize % 2)
        }

        guard let format else { throw DecodeError.unsupportedFormat("no format chunk") }
        guard format.audioFormat == 1, format.bitsPerSample == 16 else {
            throw DecodeError.unsupportedFormat("format \(format.audioFormat), \(format.bitsPerSample)-bit")
        }
        guard format.channels > 0 else { throw DecodeError.unsupportedFormat("no channels") }
        guard format.sampleRate == Self.requiredSampleRate else {
            throw DecodeError.unsupportedFormat("\(format.sampleRate) Hz")
        }
        guard let dataRange, !dataRange.isEmpty else { throw DecodeError.missingAudioData }

        let channels = format.channels
        let frameByteCount = channels * 2
        let frameCount = dataRange.count / frameByteCount
        guard frameCount > 0 else { throw DecodeError.missingAudioData }

        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        let scale = Float(Int16.max)
        for frame in 0..<frameCount {
            let frameStart = dataRange.lowerBound + frame * frameByteCount
            var sum: Float = 0
            for channel in 0..<channels {
                let raw = Int16(bitPattern: Self.uint16LE(bytes, at: frameStart + channel * 2))
                sum += Float(raw) / scale
            }
            samples.append(sum / Float(channels))
        }
        return samples
    }

    private static func fourCC(_ bytes: [UInt8], at offset: Int) -> String {
        guard offset + 4 <= bytes.count else { return "" }
        return String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    private static func uint16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
