import AVFoundation
import Foundation
import WatchKit

/// Handles audio recording and playback on Apple Watch
class WatchAudioManager: NSObject, ObservableObject {
    static let shared = WatchAudioManager()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentPlaybackSender: String?
    @Published var lastReceivedSender: String?
    @Published var lastReceivedMessage: VoiceMessage?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var playbackQueue: [VoiceMessage] = []
    private var isPlayingFromQueue = false
    private var extendedSession: WKExtendedRuntimeSession?

    private var recordingURL: URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("watch_recording.m4a")
    }

    override init() {
        super.init()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[Watch Audio] Session config error: \(error)")
        }
    }

    // MARK: - Extended Runtime Session

    /// Keeps the app running for audio playback when wrist is down
    func startExtendedSession() {
        guard extendedSession == nil || extendedSession?.state == .invalid else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
        print("[Watch Audio] Extended session started")
    }

    func stopExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }

    // MARK: - Recording

    func startRecording() {
        configureAudioSession()

        // Watch-appropriate: AAC, 16kHz mono, low bitrate
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
            AVEncoderBitRateKey: 24000,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0

            // Haptic: recording started
            WKInterfaceDevice.current().play(.start)

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            print("[Watch Audio] Recording error: \(error)")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func stopRecording() -> (Data, TimeInterval)? {
        recordingTimer?.invalidate()
        recordingTimer = nil

        guard let recorder = audioRecorder, recorder.isRecording else {
            isRecording = false
            return nil
        }

        let duration = recorder.currentTime
        recorder.stop()
        isRecording = false

        // Minimum 0.3s to avoid accidental taps
        guard duration >= 0.3 else {
            WKInterfaceDevice.current().play(.failure)
            return nil
        }

        do {
            let data = try Data(contentsOf: recordingURL)
            WKInterfaceDevice.current().play(.success)
            return (data, duration)
        } catch {
            print("[Watch Audio] Failed to read recording: \(error)")
            WKInterfaceDevice.current().play(.failure)
            return nil
        }
    }

    // MARK: - Playback

    func enqueueAndPlay(_ message: VoiceMessage) {
        lastReceivedSender = message.senderName
        lastReceivedMessage = message
        playbackQueue.append(message)
        if !isPlayingFromQueue {
            playNext()
        }
    }

    func replayLast() {
        guard let msg = lastReceivedMessage else { return }
        playbackQueue.insert(msg, at: 0)
        if !isPlayingFromQueue {
            playNext()
        }
    }

    private func playNext() {
        guard !playbackQueue.isEmpty else {
            isPlayingFromQueue = false
            isPlaying = false
            currentPlaybackSender = nil
            return
        }

        isPlayingFromQueue = true
        let message = playbackQueue.removeFirst()
        play(message)
    }

    private func play(_ message: VoiceMessage) {
        configureAudioSession()
        startExtendedSession()

        // Haptic before playback
        WKInterfaceDevice.current().play(.notification)

        do {
            audioPlayer = try AVAudioPlayer(data: message.audioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            currentPlaybackSender = message.senderName
        } catch {
            print("[Watch Audio] Playback error: \(error)")
            playNext()
        }
    }

    // MARK: - Volume (Crown)

    func adjustVolume(by delta: Double) {
        guard let player = audioPlayer else { return }
        let newVolume = max(0, min(1, player.volume + Float(delta)))
        player.volume = newVolume
    }
}

// MARK: - AVAudioPlayerDelegate

extension WatchAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.playNext()
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchAudioManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[Watch Audio] Extended session active")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[Watch Audio] Extended session expiring")
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        print("[Watch Audio] Extended session invalidated: \(reason)")
        extendedSession = nil
    }
}
