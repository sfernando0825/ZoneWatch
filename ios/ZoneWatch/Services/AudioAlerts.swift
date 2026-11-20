import AVFoundation
import Observation
import ZoneWatchKit

/// Plays alert prompts (a chime followed by speech) so they are heard with the ringer switch on silent.
///
/// Prompts are made with on-device text-to-speech once and saved as audio files, because live speech
/// can pause when the screen locks. Playback uses the `.playback` category, which the silent switch
/// does not mute, with the `.voicePrompt` mode Apple asks navigation-style apps to use.
@MainActor
@Observable
final class AudioAlerts {
    enum Prompt: String, CaseIterable {
        case speedCamera, mobileCamera, phoneCamera, phoneAndSeatbeltCamera, redLightCamera, averageSpeedZone, test

        var text: String {
            switch self {
            case .speedCamera: "Speed camera ahead"
            case .mobileCamera: "Mobile camera ahead"
            case .phoneCamera: "Phone camera ahead"
            case .phoneAndSeatbeltCamera: "Phone and seatbelt camera ahead"
            case .redLightCamera: "Red light camera ahead"
            case .averageSpeedZone: "Average speed zone ahead"
            case .test: "ZoneWatch test alert. Speed camera ahead"
            }
        }

        static func forCamera(_ type: CameraType) -> Prompt {
            switch type {
            case .fixedSpeed, .pointToPointEnd: .speedCamera
            case .mobileSpeed: .mobileCamera
            case .phoneCamera: .phoneCamera
            case .phoneAndSeatbeltCamera: .phoneAndSeatbeltCamera
            case .redLightSpeed: .redLightCamera
            case .pointToPointStart: .averageSpeedZone
            }
        }
    }

    /// Bump when prompt wording or the chime changes, so saved files are made again.
    private static let promptVersion = 1

    private(set) var preparedCount = 0
    private(set) var lastError: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    var outputVolume: Float { AVAudioSession.sharedInstance().outputVolume }
    var promptCount: Int { Prompt.allCases.count }

    /// Makes any missing prompt files. Run in the foreground at launch.
    func prepare() async {
        var ready = 0
        for prompt in Prompt.allCases {
            let url = Self.url(for: prompt)
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try await PromptRenderer.render(prompt.text, to: url)
                } catch {
                    lastError = "Could not make \"\(prompt.text)\": \(error.localizedDescription)"
                    continue
                }
            }
            ready += 1
            preparedCount = ready
        }
    }

    func play(_ prompt: Prompt) {
        let url = Self.url(for: prompt)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "Prompt not ready: \(prompt.text)"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            lastError = nil
            scheduleRelease(after: player.duration)
        } catch {
            lastError = "Playback failed: \(error.localizedDescription)"
        }
    }

    /// Hand audio back to other apps (music, podcasts) straight after the prompt, as Apple's guidance requires.
    private func scheduleRelease(after duration: TimeInterval) {
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(duration + 0.3))
            guard !Task.isCancelled else { return }
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func url(for prompt: Prompt) -> URL {
        let folder = URL.applicationSupportDirectory.appending(path: "Prompts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(prompt.rawValue)-v\(promptVersion).caf")
    }
}

/// Renders text to an audio file with on-device speech, preceded by a short chime.
enum PromptRenderer {
    @MainActor
    static func render(_ text: String, to url: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        let sink = PromptFileSink(url: url)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sink.continuation = continuation
            synthesizer.write(utterance) { buffer in
                sink.consume(buffer)
            }
        }
        withExtendedLifetime(synthesizer) {}
    }
}

enum PromptRenderError: Error {
    case unsupportedBuffer
    case noAudio
}

/// Collects speech buffers into a file. The synthesizer calls back on its own queue, hence the lock.
private final class PromptFileSink: @unchecked Sendable {
    let url: URL
    var continuation: CheckedContinuation<Void, any Error>?
    private var file: AVAudioFile?
    private var finished = false
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            finish(.failure(PromptRenderError.unsupportedBuffer))
            return
        }
        // The synthesizer marks the end with an empty buffer.
        if pcm.frameLength == 0 {
            finish(file == nil ? .failure(PromptRenderError.noAudio) : .success(()))
            return
        }
        do {
            if file == nil {
                try? FileManager.default.removeItem(at: url)
                let created = try AVAudioFile(
                    forWriting: url,
                    settings: pcm.format.settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: pcm.format.isInterleaved
                )
                if let chime = Chime.buffer(format: pcm.format) {
                    try created.write(from: chime)
                }
                file = created
            }
            try file?.write(from: pcm)
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, any Error>) {
        finished = true
        file = nil
        if case .failure = result { try? FileManager.default.removeItem(at: url) }
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// Two rising tones and a short pause, in the same format as the speech that follows.
private enum Chime {
    static func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let notes: [(frequency: Double, seconds: Double)] = [(880, 0.14), (0, 0.06), (1_320, 0.2), (0, 0.25)]
        let totalFrames = AVAudioFrameCount(notes.reduce(0) { $0 + $1.seconds } * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        buffer.frameLength = totalFrames

        var samples: [Float] = []
        samples.reserveCapacity(Int(totalFrames))
        for note in notes {
            let frames = Int(note.seconds * rate)
            for i in 0..<frames {
                guard note.frequency > 0 else { samples.append(0); continue }
                let fade = min(1, Double(min(i, frames - i)) / (0.01 * rate))
                samples.append(Float(sin(2 * .pi * note.frequency * Double(i) / rate) * 0.6 * fade))
            }
        }
        let count = min(samples.count, Int(totalFrames))
        let channels = Int(format.channelCount)

        if let floats = buffer.floatChannelData {
            for channel in 0..<channels {
                for i in 0..<count { floats[channel][i] = samples[i] }
            }
        } else if let ints = buffer.int16ChannelData {
            for channel in 0..<channels {
                for i in 0..<count { ints[channel][i] = Int16(samples[i] * Float(Int16.max)) }
            }
        } else {
            return nil
        }
        return buffer
    }
}
