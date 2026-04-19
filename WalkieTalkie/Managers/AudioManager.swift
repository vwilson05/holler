import AVFoundation
import Foundation
import Combine
import UIKit

/// Handles AAC audio recording via AVAudioEngine and queued playback
final class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var playbackSender: String? = nil
    @Published var currentPlaybackMessageID: UUID? = nil

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var playbackQueue: [VoiceMessage] = []
    private var isPlayingFromQueue = false

    /// Silent audio player for background keep-alive
    private var silentPlayer: AVAudioPlayer?
    private var isInBackground = false

    /// Callback fired before each message plays (for haptic identity)
    var onWillPlayMessage: ((VoiceMessage) -> Void)?

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("holler_recording.m4a")
    }

    private var settings: AppSettings { AppSettings.shared }

    override init() {
        super.init()
        configureAudioSession()
        prepareSilentAudio()
        observeAppLifecycle()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true)
        } catch {
            print("[Audio] Session config error: \(error)")
        }

        // Observe audio interruptions (phone calls, Siri, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("[Audio] Interruption began (phone call, Siri, etc.)")
            // Pause playback gracefully
            if isPlaying {
                audioPlayer?.pause()
            }
            silentPlayer?.pause()

        case .ended:
            print("[Audio] Interruption ended")
            // Re-activate session and resume
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(true)
            } catch {
                print("[Audio] Failed to reactivate session: \(error)")
            }

            if let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                audioPlayer?.play()
            }

            // Resume silent loop if in background
            if isInBackground {
                startSilentLoop()
            }

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable {
            // Headphones unplugged - audio routes to speaker, keep playing
            print("[Audio] Route changed: old device unavailable, continuing playback")
        }
    }

    // MARK: - Background Audio Keep-Alive

    private func prepareSilentAudio() {
        // Generate a near-silent audio buffer (1s at 8kHz mono)
        // Must be non-zero volume — iOS detects true silence and suspends the app
        let sampleRate: Double = 8000
        let duration: Double = 1.0
        let numSamples = Int(sampleRate * duration)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            print("[Audio] Failed to create silent buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(numSamples)

        // Fill with near-silence (tiny amplitude — inaudible but non-zero)
        if let channelData = buffer.floatChannelData {
            for i in 0..<numSamples {
                channelData[0][i] = Float.random(in: -0.0001...0.0001)
            }
        }

        // Write to a temporary file
        let silentURL = FileManager.default.temporaryDirectory.appendingPathComponent("holler_silent.wav")
        do {
            try? FileManager.default.removeItem(at: silentURL)
            let file = try AVAudioFile(forWriting: silentURL, settings: format.settings)
            try file.write(from: buffer)

            silentPlayer = try AVAudioPlayer(contentsOf: silentURL)
            silentPlayer?.numberOfLoops = -1 // Loop forever
            silentPlayer?.volume = 0.01 // Near-silent but non-zero to keep audio session alive
            silentPlayer?.prepareToPlay()
        } catch {
            print("[Audio] Failed to prepare silent audio: \(error)")
        }
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        isInBackground = true
        if settings.stayActiveInBackground {
            startSilentLoop()
            print("[Audio] Background: stay-active ON — started silent audio loop")
        } else {
            print("[Audio] Background: stay-active OFF — relying on notifications")
        }
    }

    @objc private func appWillEnterForeground() {
        isInBackground = false
        stopSilentLoop()
        print("[Audio] Foreground: stopped silent audio loop")
    }

    private func startSilentLoop() {
        // Ensure audio session is active
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            print("[Audio] Failed to activate session for background: \(error)")
        }
        silentPlayer?.play()
    }

    private func stopSilentLoop() {
        silentPlayer?.stop()
    }

    // MARK: - Recording

    func startRecording() {
        configureAudioSession()

        // Use AVAudioRecorder — handles sample rate conversion cleanly
        startRecordingFallback()
    }

    /// Fallback recording using AVAudioRecorder if AVAudioEngine fails
    private var fallbackRecorder: AVAudioRecorder?

    private func startRecordingFallback() {
        let recorderSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: settings.audioQuality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: settings.audioQuality.bitRate,
        ]

        do {
            try? FileManager.default.removeItem(at: recordingURL)
            fallbackRecorder = try AVAudioRecorder(url: recordingURL, settings: recorderSettings)
            fallbackRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            print("[Audio] Fallback recorder error: \(error)")
        }
    }

    func stopRecording() -> (Data, Int)? {
        recordingTimer?.invalidate()
        recordingTimer = nil

        let duration = recordingDuration
        isRecording = false

        // Stop engine recording
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioFile = nil
        }

        // Stop fallback recorder
        if let recorder = fallbackRecorder, recorder.isRecording {
            recorder.stop()
            fallbackRecorder = nil
        }

        // Minimum 0.3s to prevent accidental taps
        guard duration >= 0.3 else {
            return nil
        }

        do {
            let data = try Data(contentsOf: recordingURL)
            let durationMs = Int(duration * 1000)
            return (data, durationMs)
        } catch {
            print("[Audio] Failed to read recording: \(error)")
            return nil
        }
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioFile = nil
        }

        if let recorder = fallbackRecorder, recorder.isRecording {
            recorder.stop()
            fallbackRecorder = nil
        }
    }

    private func stopEngineIfNeeded() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    // MARK: - Playback Queue

    func enqueueAndPlay(_ message: VoiceMessage) {
        playbackQueue.append(message)
        if !isPlayingFromQueue {
            playNext()
        }
    }

    func playMessage(_ message: VoiceMessage) {
        // Direct play (tap to replay)
        playbackQueue.removeAll()
        isPlayingFromQueue = false
        play(message)
    }

    private func playNext() {
        guard !playbackQueue.isEmpty else {
            isPlayingFromQueue = false
            isPlaying = false
            playbackSender = nil
            currentPlaybackMessageID = nil
            return
        }

        isPlayingFromQueue = true
        let message = playbackQueue.removeFirst()

        // Fire haptic callback before playing
        onWillPlayMessage?(message)

        // Small delay for haptic to play first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.play(message)
        }
    }

    private func play(_ message: VoiceMessage) {
        configureAudioSession()

        do {
            audioPlayer = try AVAudioPlayer(data: message.audioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            playbackSender = message.senderName
            currentPlaybackMessageID = message.id
        } catch {
            print("[Audio] Playback error: \(error)")
            playNext()
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        playbackQueue.removeAll()
        isPlayingFromQueue = false
        isPlaying = false
        playbackSender = nil
        currentPlaybackMessageID = nil
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.playNext()
        }
    }
}
