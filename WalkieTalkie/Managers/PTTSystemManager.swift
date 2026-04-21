import Foundation
import PushToTalk
import AVFoundation
import UIKit
import Combine

/// Wraps Apple's PTChannelManager to provide system-level PTT UI.
/// The system PTT button appears as a floating pill (like phone calls)
/// accessible from lock screen, other apps, and anywhere on the system.
/// Supports handsfree accessory buttons (Bluetooth PTT devices).
@MainActor
final class PTTSystemManager: NSObject, ObservableObject {
    static let shared = PTTSystemManager()

    @Published var isSystemPTTActive = false
    @Published var isTransmitting = false
    @Published var systemPTTError: String?
    @Published var pushToken: Data?

    private var channelManager: PTChannelManager?
    private var activeChannelUUID: UUID?

    /// Callbacks for integration with ConnectionManager
    var onTransmissionStarted: (() -> Void)?
    var onTransmissionEnded: ((Data?, Int) -> Void)?
    var onAudioSessionActivated: ((AVAudioSession) -> Void)?
    var onAudioSessionDeactivated: ((AVAudioSession) -> Void)?
    var onPushTokenReceived: ((Data) -> Void)?

    /// Recording state for system-initiated transmissions
    private var systemRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("holler_system_ptt.m4a")
    }

    override init() {
        super.init()
    }

    // MARK: - Setup

    /// Initialize the PTChannelManager. Call this early in app lifecycle.
    func setup() {
        PTChannelManager.channelManager(delegate: self, restorationDelegate: self) { [weak self] manager, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[SystemPTT] Failed to create channel manager: \(error)")
                    self?.systemPTTError = error.localizedDescription
                    return
                }
                self?.channelManager = manager
                self?.isSystemPTTActive = true
                print("[SystemPTT] Channel manager created successfully")

                // Check if there's an active channel from restoration
                if let activeUUID = manager?.activeChannelUUID {
                    print("[SystemPTT] Restored active channel: \(activeUUID)")
                    self?.activeChannelUUID = activeUUID
                }
            }
        }
    }

    // MARK: - Channel Management

    /// Join a channel with the system PTT UI. This shows the floating pill.
    func joinChannel(channelUUID: UUID, channelName: String, channelImage: UIImage? = nil) {
        guard let channelManager = channelManager else {
            print("[SystemPTT] Channel manager not ready")
            return
        }

        let descriptor = PTChannelDescriptor(name: channelName, image: channelImage)
        channelManager.requestJoinChannel(channelUUID: channelUUID, descriptor: descriptor)
        activeChannelUUID = channelUUID
        print("[SystemPTT] Requested join channel: \(channelName) (\(channelUUID))")
    }

    /// Leave the current system PTT channel. Removes the floating pill.
    func leaveChannel() {
        guard let channelManager = channelManager, let uuid = activeChannelUUID else { return }
        channelManager.leaveChannel(channelUUID: uuid)
        print("[SystemPTT] Requested leave channel: \(uuid)")
    }

    /// Update the channel descriptor (name/image) while active.
    func updateChannel(channelName: String, channelImage: UIImage? = nil) {
        guard let channelManager = channelManager, let uuid = activeChannelUUID else { return }
        let descriptor = PTChannelDescriptor(name: channelName, image: channelImage)
        channelManager.setChannelDescriptor(descriptor, channelUUID: uuid) { error in
            if let error { print("[SystemPTT] Failed to update descriptor: \(error)") }
        }
    }

    // MARK: - Transmission Control

    /// Request to begin transmitting from within the app (programmatic).
    func beginTransmitting() {
        guard let channelManager = channelManager, let uuid = activeChannelUUID else {
            print("[SystemPTT] Cannot transmit - no active channel")
            return
        }
        channelManager.requestBeginTransmitting(channelUUID: uuid)
        print("[SystemPTT] Requested begin transmitting")
    }

    /// Stop transmitting.
    func stopTransmitting() {
        guard let channelManager = channelManager, let uuid = activeChannelUUID else { return }
        channelManager.stopTransmitting(channelUUID: uuid)
        print("[SystemPTT] Stopped transmitting")
    }

    // MARK: - Service Status

    func setServiceReady(on channelUUID: UUID) {
        guard let channelManager = channelManager else { return }
        channelManager.setServiceStatus(.ready, channelUUID: channelUUID) { _ in }
    }

    /// Report active speaker for incoming audio.
    func reportIncomingSpeaker(name: String, on channelUUID: UUID) {
        guard let channelManager = channelManager else { return }
        let participant = PTParticipant(name: name, image: nil)
        channelManager.setActiveRemoteParticipant(participant, channelUUID: channelUUID) { _ in }
    }

    /// Clear active speaker.
    func clearIncomingSpeaker(on channelUUID: UUID) {
        guard let channelManager = channelManager else { return }
        channelManager.setActiveRemoteParticipant(nil, channelUUID: channelUUID) { _ in }
    }

    // MARK: - Recording Helpers

    private func startSystemRecording(audioSession: AVAudioSession) {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            systemRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            systemRecorder?.record()
            recordingStartTime = Date()
            isTransmitting = true
            print("[SystemPTT] System recording started")
        } catch {
            print("[SystemPTT] Failed to start system recording: \(error)")
        }
    }

    private func stopSystemRecording() -> (Data, Int)? {
        guard let recorder = systemRecorder, recorder.isRecording else { return nil }

        recorder.stop()
        isTransmitting = false

        let durationMs = Int((Date().timeIntervalSince(recordingStartTime ?? Date())) * 1000)

        guard durationMs >= 300 else {
            print("[SystemPTT] Recording too short (\(durationMs)ms), discarding")
            return nil
        }

        do {
            let data = try Data(contentsOf: recordingURL)
            print("[SystemPTT] System recording stopped: \(durationMs)ms, \(data.count) bytes")
            return (data, durationMs)
        } catch {
            print("[SystemPTT] Failed to read recording: \(error)")
            return nil
        }
    }
}

// MARK: - PTChannelManagerDelegate

extension PTTSystemManager: PTChannelManagerDelegate {
    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        Task { @MainActor in
            self.activeChannelUUID = channelUUID
            print("[SystemPTT] Joined channel: \(channelUUID), reason: \(reason)")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        Task { @MainActor in
            if self.activeChannelUUID == channelUUID {
                self.activeChannelUUID = nil
            }
            print("[SystemPTT] Left channel: \(channelUUID), reason: \(reason)")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in
            self.isTransmitting = true
            self.onTransmissionStarted?()
            print("[SystemPTT] Began transmitting from source: \(source.rawValue)")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in
            if let (audioData, durationMs) = self.stopSystemRecording() {
                self.onTransmissionEnded?(audioData, durationMs)
            } else {
                self.onTransmissionEnded?(nil, 0)
            }
            self.isTransmitting = false
            print("[SystemPTT] Ended transmitting from source: \(source.rawValue)")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        Task { @MainActor in
            self.pushToken = pushToken
            self.onPushTokenReceived?(pushToken)
            let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
            print("[SystemPTT] Received push token: \(tokenString.prefix(16))...")
        }
    }

    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        if let senderName = pushPayload["sender"] as? String {
            let participant = PTParticipant(name: senderName, image: nil)
            return PTPushResult.activeRemoteParticipant(participant)
        }
        return PTPushResult.leaveChannel
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.startSystemRecording(audioSession: audioSession)
            self.onAudioSessionActivated?(audioSession)
            print("[SystemPTT] Audio session activated")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.onAudioSessionDeactivated?(audioSession)
            print("[SystemPTT] Audio session deactivated")
        }
    }

    // Optional error handlers
    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in
            self.systemPTTError = "Failed to join: \(error.localizedDescription)"
            print("[SystemPTT] Failed to join channel: \(error)")
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in
            self.systemPTTError = "Failed to transmit: \(error.localizedDescription)"
            print("[SystemPTT] Failed to begin transmitting: \(error)")
        }
    }
}

// MARK: - PTChannelRestorationDelegate

extension PTTSystemManager: PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        let channelName = AppSettings.shared.activeChannel?.name ?? "Holler"
        print("[SystemPTT] Restoring channel descriptor for: \(channelUUID)")
        return PTChannelDescriptor(name: channelName, image: nil)
    }
}
