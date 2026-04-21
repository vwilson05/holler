import Foundation
import UserNotifications
import UIKit
import Combine
import AVFoundation

/// Orchestrates Multipeer + WebSocket, deduplicates messages, manages per-channel state
final class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()

    /// Messages keyed by channel ID
    @Published var messagesByChannel: [UUID: [VoiceMessage]] = [:]
    /// Members keyed by channel ID
    @Published var membersByChannel: [UUID: [Member]] = [:]
    /// Member locations keyed by member ID
    @Published var memberLocations: [String: (lat: Double, lng: Double, accuracy: Double)] = [:]

    @Published var lanPeerCount: Int = 0
    @Published var wsConnected: Bool = false
    @Published var isActive = false

    private let multipeer = MultipeerManager.shared
    private let ws = WebSocketManager.shared
    private let audio = AudioManager.shared
    private let settings = AppSettings.shared
    private let haptic = HapticManager.shared
    private let transcription = TranscriptionManager.shared

    private var seenMessageIDs = Set<String>()
    private let maxMessagesPerChannel = 100
    private var cancellables = Set<AnyCancellable>()

    private var backgroundReconnectTimer: Timer?

    private init() {
        setupCallbacks()
        requestNotificationPermission()
        observeAppLifecycle()
    }

    // MARK: - Messages for active channel

    var activeChannelMessages: [VoiceMessage] {
        guard let channelID = settings.activeChannelID else { return [] }
        return messagesByChannel[channelID] ?? []
    }

    var activeChannelMembers: [Member] {
        guard let channelID = settings.activeChannelID else { return [] }
        return membersByChannel[channelID] ?? []
    }

    // MARK: - Start / Stop

    func start() {
        guard settings.isSetUp else { return }
        guard let channel = settings.activeChannel else { return }

        // Start Multipeer (LAN) unless relay-only
        if channel.connectionMode != .relay {
            multipeer.start(displayName: settings.displayName, roomCode: channel.code)
        }

        // Start WebSocket (Internet) unless LAN-only
        if channel.connectionMode != .lan && !settings.relayServerURL.isEmpty {
            ws.connect(
                url: settings.relayServerURL,
                room: channel.code,
                memberID: settings.deviceID,
                memberName: settings.displayName
            )
        }

        // Add self to channel members
        let selfMember = Member(
            id: settings.deviceID,
            name: settings.displayName,
            isOnline: true
        )
        addMember(selfMember, to: channel.id)

        isActive = true
        print("[Connection] Started for channel: \(channel.name) (\(channel.code))")

        // Wire system PTT callbacks to send audio through our pipeline
        Task { @MainActor in
            PTTSystemManager.shared.onTransmissionEnded = { [weak self] audioData, durationMs in
                guard let self, let audioData, durationMs > 0 else { return }
                self.sendVoice(audioData: audioData, durationMs: durationMs)
            }

            // Join system PTT channel if not already active
            if PTTSystemManager.shared.isSystemPTTActive {
                PTTSystemManager.shared.joinChannel(
                    channelUUID: channel.id,
                    channelName: channel.name
                )
            }
        }
    }

    func stop() {
        guard let channel = settings.activeChannel else {
            multipeer.stop()
            ws.disconnect()
            isActive = false
            return
        }

        // Send leave
        if !settings.relayServerURL.isEmpty {
            ws.sendLeave(room: channel.code, senderName: settings.displayName, senderID: settings.deviceID)
        }

        multipeer.stop()
        ws.disconnect()
        isActive = false
        print("[Connection] Stopped")
    }

    func switchChannel(to channel: Channel) {
        stop()

        // Leave previous system PTT channel
        Task { @MainActor in PTTSystemManager.shared.leaveChannel() }

        settings.activeChannelID = channel.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()

            // Join system PTT channel (shows floating pill UI)
            PTTSystemManager.shared.joinChannel(
                channelUUID: channel.id,
                channelName: channel.name
            )
        }
    }

    // MARK: - Send Voice

    func sendVoice(audioData: Data, durationMs: Int) {
        guard let channel = settings.activeChannel else { return }

        let messageID = UUID()
        let base64Audio = audioData.base64EncodedString()

        let wireMsg = WireMessage(
            type: .voice,
            id: messageID.uuidString,
            sender: settings.displayName,
            senderID: settings.deviceID,
            room: channel.code,
            payload: .voice(WirePayload.VoicePayload(audio: base64Audio, durationMs: durationMs))
        )

        // Send via channels based on connection mode
        if channel.connectionMode != .relay {
            multipeer.send(wireMsg)
        }
        if channel.connectionMode != .lan && !settings.relayServerURL.isEmpty {
            ws.send(wireMsg)
        }

        // Add to local messages
        let voiceMsg = VoiceMessage(
            id: messageID,
            senderID: settings.deviceID,
            senderName: settings.displayName,
            channelID: channel.id,
            durationMs: durationMs,
            audioData: audioData,
            isPlayed: true
        )
        addMessage(voiceMsg, to: channel.id)

        // Transcribe own message
        transcription.transcribe(audioData: audioData) { [weak self] text in
            self?.updateTranscription(messageID: messageID, channelID: channel.id, text: text)

            // Send transcription to peers
            let transMsg = WireMessage(
                type: .transcription,
                sender: self?.settings.displayName ?? "",
                senderID: self?.settings.deviceID ?? "",
                room: channel.code,
                payload: .transcription(WirePayload.TranscriptionPayload(messageID: messageID.uuidString, text: text))
            )
            if channel.connectionMode != .relay {
                self?.multipeer.send(transMsg)
            }
            if channel.connectionMode != .lan && !(self?.settings.relayServerURL.isEmpty ?? true) {
                self?.ws.send(transMsg)
            }
        }

        print("[Connection] Sent voice: \(durationMs)ms, \(audioData.count) bytes")
    }

    // MARK: - Send Location

    func sendLocation(lat: Double, lng: Double, accuracy: Double) {
        guard let channel = settings.activeChannel else { return }

        let wireMsg = WireMessage(
            type: .location,
            sender: settings.displayName,
            senderID: settings.deviceID,
            room: channel.code,
            payload: .location(WirePayload.LocationPayload(lat: lat, lng: lng, accuracy: accuracy))
        )

        if channel.connectionMode != .relay {
            multipeer.send(wireMsg)
        }
        if channel.connectionMode != .lan && !settings.relayServerURL.isEmpty {
            ws.send(wireMsg)
        }

        // Update own location
        memberLocations[settings.deviceID] = (lat, lng, accuracy)
    }

    // MARK: - Send Reaction

    func sendReaction(emoji: String, toMessageID messageID: UUID) {
        guard let channel = settings.activeChannel else { return }

        let wireMsg = WireMessage(
            type: .reaction,
            sender: settings.displayName,
            senderID: settings.deviceID,
            room: channel.code,
            payload: .reaction(WirePayload.ReactionPayload(messageID: messageID.uuidString, emoji: emoji))
        )

        if channel.connectionMode != .relay {
            multipeer.send(wireMsg)
        }
        if channel.connectionMode != .lan && !settings.relayServerURL.isEmpty {
            ws.send(wireMsg)
        }

        // Add locally
        let reaction = MessageReaction(senderID: settings.deviceID, senderName: settings.displayName, emoji: emoji)
        addReaction(reaction, toMessage: messageID, inChannel: channel.id)

        print("[Connection] Sent reaction \(emoji) on \(messageID)")
    }

    private func addReaction(_ reaction: MessageReaction, toMessage messageID: UUID, inChannel channelID: UUID) {
        guard var messages = messagesByChannel[channelID] else { return }
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            // Don't duplicate — one reaction per sender
            messages[idx].reactions.removeAll(where: { $0.senderID == reaction.senderID })
            messages[idx].reactions.append(reaction)
            messagesByChannel[channelID] = messages
        }
    }

    private static let emojiNames: [String: String] = [
        "👍": "thumbs up",
        "❤️": "love",
        "😂": "haha",
        "🔥": "fire"
    ]

    private let speechSynth = AVSpeechSynthesizer()

    private func announceReaction(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2
        utterance.volume = 0.6
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynth.speak(utterance)
    }

    // MARK: - Receive

    private func setupCallbacks() {
        multipeer.onMessageReceived = { [weak self] wireMsg in
            self?.handleIncoming(wireMsg, via: "LAN")
        }

        ws.onMessageReceived = { [weak self] wireMsg in
            self?.handleIncoming(wireMsg, via: "WS")
        }

        // Set up haptic identity for audio playback
        audio.onWillPlayMessage = { [weak self] message in
            self?.playHapticForSender(message.senderID, channelID: message.channelID)
        }

        // Observe peer counts
        multipeer.$connectedPeers
            .map { $0.count }
            .receive(on: DispatchQueue.main)
            .assign(to: &$lanPeerCount)

        ws.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$wsConnected)
    }

    private func handleIncoming(_ wireMsg: WireMessage, via channel: String) {
        // Don't process our own messages
        guard wireMsg.senderID != settings.deviceID else { return }

        // Deduplicate
        guard !seenMessageIDs.contains(wireMsg.id) else {
            print("[Connection] Duplicate message ignored via \(channel)")
            return
        }
        seenMessageIDs.insert(wireMsg.id)

        // Find matching channel by room code
        guard let matchingChannel = settings.channels.first(where: { $0.code == wireMsg.room }) else {
            print("[Connection] No channel found for room: \(wireMsg.room)")
            return
        }

        switch wireMsg.type {
        case .voice:
            guard case .voice(let voicePayload) = wireMsg.payload else { return }
            guard let audioData = Data(base64Encoded: voicePayload.audio) else {
                print("[Connection] Failed to decode audio data")
                return
            }

            let messageID = UUID(uuidString: wireMsg.id) ?? UUID()
            let voiceMsg = VoiceMessage(
                id: messageID,
                senderID: wireMsg.senderID,
                senderName: wireMsg.sender,
                channelID: matchingChannel.id,
                timestamp: Date(timeIntervalSince1970: TimeInterval(wireMsg.timestamp) / 1000),
                durationMs: voicePayload.durationMs,
                audioData: audioData
            )

            addMessage(voiceMsg, to: matchingChannel.id)

            // Update member as online
            let member = Member(id: wireMsg.senderID, name: wireMsg.sender, isOnline: true)
            addMember(member, to: matchingChannel.id)

            // Check if member is muted
            let existingMember = membersByChannel[matchingChannel.id]?.first(where: { $0.id == wireMsg.senderID })
            if existingMember?.isMuted != true {
                // Auto-play if this is the active channel
                if matchingChannel.id == settings.activeChannelID {
                    audio.enqueueAndPlay(voiceMsg)
                    // Show active speaker on system PTT UI
                    let senderName = wireMsg.sender
                    let channelID = matchingChannel.id
                    let clearDelay = Double(voicePayload.durationMs) / 1000.0 + 0.5
                    Task { @MainActor in
                        PTTSystemManager.shared.reportIncomingSpeaker(name: senderName, on: channelID)
                        try? await Task.sleep(for: .seconds(clearDelay))
                        PTTSystemManager.shared.clearIncomingSpeaker(on: channelID)
                    }
                }
                sendLocalNotification(from: wireMsg.sender, durationMs: voicePayload.durationMs)
            }

            // Transcribe incoming message
            transcription.transcribe(audioData: audioData) { [weak self] text in
                self?.updateTranscription(messageID: messageID, channelID: matchingChannel.id, text: text)
            }

            print("[Connection] Received voice from \(wireMsg.sender) via \(channel): \(voicePayload.durationMs)ms")

        case .location:
            guard case .location(let locPayload) = wireMsg.payload else { return }
            memberLocations[wireMsg.senderID] = (locPayload.lat, locPayload.lng, locPayload.accuracy)
            print("[Connection] Location from \(wireMsg.sender): \(locPayload.lat), \(locPayload.lng)")

        case .join:
            let member = Member(id: wireMsg.senderID, name: wireMsg.sender, isOnline: true)
            addMember(member, to: matchingChannel.id)
            print("[Connection] \(wireMsg.sender) joined via \(channel)")

        case .leave:
            if let idx = membersByChannel[matchingChannel.id]?.firstIndex(where: { $0.id == wireMsg.senderID }) {
                membersByChannel[matchingChannel.id]?[idx].isOnline = false
                membersByChannel[matchingChannel.id]?[idx].lastActiveAt = Date()
            }
            print("[Connection] \(wireMsg.sender) left via \(channel)")

        case .members:
            guard case .members(let membersPayload) = wireMsg.payload else { return }
            for memberInfo in membersPayload.members {
                let member = Member(
                    id: memberInfo.id,
                    name: memberInfo.name,
                    isOnline: memberInfo.online
                )
                addMember(member, to: matchingChannel.id)
            }

        case .transcription:
            guard case .transcription(let transPayload) = wireMsg.payload else { return }
            if let messageID = UUID(uuidString: transPayload.messageID) {
                updateTranscription(messageID: messageID, channelID: matchingChannel.id, text: transPayload.text)
            }

        case .reaction:
            guard case .reaction(let reactionPayload) = wireMsg.payload else { return }
            if let messageID = UUID(uuidString: reactionPayload.messageID) {
                let reaction = MessageReaction(
                    senderID: wireMsg.senderID,
                    senderName: wireMsg.sender,
                    emoji: reactionPayload.emoji
                )
                addReaction(reaction, toMessage: messageID, inChannel: matchingChannel.id)

                // TTS announcement for hands-free
                let emojiName = Self.emojiNames[reactionPayload.emoji] ?? "reacted to"
                let announcement = "\(wireMsg.sender): \(emojiName)"
                announceReaction(announcement)

                print("[Connection] Reaction from \(wireMsg.sender): \(reactionPayload.emoji) on \(reactionPayload.messageID)")
            }

        case .ping, .pong:
            break
        }

        // Trim seen IDs
        if seenMessageIDs.count > 1000 {
            let keepCount = 500
            seenMessageIDs = Set(seenMessageIDs.suffix(keepCount))
        }
    }

    // MARK: - Background / Foreground Lifecycle

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

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    @objc private func appDidEnterBackground() {
        print("[Connection] App entered background - keeping WebSocket alive")

        // Request extended background execution time
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "HollerKeepAlive") { [weak self] in
            // Expiration handler
            if let self, self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }

        // Start a periodic check to reconnect WebSocket if it drops
        backgroundReconnectTimer?.invalidate()
        backgroundReconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.isActive else { return }
            if !self.ws.isConnected && !self.settings.relayServerURL.isEmpty {
                guard let channel = self.settings.activeChannel else { return }
                guard channel.connectionMode != .lan else { return }
                print("[Connection] Background reconnect attempt")
                self.ws.connect(
                    url: self.settings.relayServerURL,
                    room: channel.code,
                    memberID: self.settings.deviceID,
                    memberName: self.settings.displayName
                )
            }
        }
    }

    @objc private func appWillEnterForeground() {
        print("[Connection] App entering foreground")
        backgroundReconnectTimer?.invalidate()
        backgroundReconnectTimer = nil

        // End background task
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        // Reconnect if needed
        if isActive && !ws.isConnected && !settings.relayServerURL.isEmpty {
            guard let channel = settings.activeChannel else { return }
            guard channel.connectionMode != .lan else { return }
            ws.connect(
                url: settings.relayServerURL,
                room: channel.code,
                memberID: settings.deviceID,
                memberName: settings.displayName
            )
        }
    }

    // MARK: - State Management

    private func addMessage(_ message: VoiceMessage, to channelID: UUID) {
        if messagesByChannel[channelID] == nil {
            messagesByChannel[channelID] = []
        }
        messagesByChannel[channelID]?.append(message)
        if let count = messagesByChannel[channelID]?.count, count > maxMessagesPerChannel {
            messagesByChannel[channelID]?.removeFirst()
        }

        // Persist latest for widget
        persistWidgetData()
    }

    private func addMember(_ member: Member, to channelID: UUID) {
        if membersByChannel[channelID] == nil {
            membersByChannel[channelID] = []
        }
        if let idx = membersByChannel[channelID]?.firstIndex(where: { $0.id == member.id }) {
            // Update existing - preserve mute/haptic settings
            let existing = membersByChannel[channelID]![idx]
            var updated = member
            updated.isMuted = existing.isMuted
            updated.hapticPattern = existing.hapticPattern
            membersByChannel[channelID]?[idx] = updated
        } else {
            // Assign a unique haptic pattern
            var newMember = member
            let usedPatterns = membersByChannel[channelID]?.map { $0.hapticPattern } ?? []
            let available = HapticPattern.allCases.filter { !usedPatterns.contains($0) }
            newMember.hapticPattern = available.first ?? HapticPattern.allCases.randomElement()!
            membersByChannel[channelID]?.append(newMember)
        }
    }

    private func updateTranscription(messageID: UUID, channelID: UUID, text: String) {
        if let idx = messagesByChannel[channelID]?.firstIndex(where: { $0.id == messageID }) {
            messagesByChannel[channelID]?[idx].transcription = text
        }
    }

    func toggleMute(memberID: String, channelID: UUID) {
        if let idx = membersByChannel[channelID]?.firstIndex(where: { $0.id == memberID }) {
            membersByChannel[channelID]?[idx].isMuted.toggle()
        }
    }

    func searchMessages(query: String, in channelID: UUID) -> [VoiceMessage] {
        let messages = messagesByChannel[channelID] ?? []
        guard !query.isEmpty else { return messages }
        return messages.filter { msg in
            msg.transcription?.localizedCaseInsensitiveContains(query) == true ||
            msg.senderName.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Haptic Identity

    private func playHapticForSender(_ senderID: String, channelID: UUID) {
        guard settings.notificationHaptic else { return }
        guard let member = membersByChannel[channelID]?.first(where: { $0.id == senderID }) else { return }
        haptic.playPattern(member.hapticPattern)
    }

    // MARK: - Widget Data

    private func persistWidgetData() {
        guard let channel = settings.activeChannel else { return }
        let defaults = UserDefaults(suiteName: "group.com.holler.shared")
        defaults?.set(channel.name, forKey: "widget_channelName")
        defaults?.set(membersByChannel[channel.id]?.count ?? 0, forKey: "widget_memberCount")

        let recentMessages = (messagesByChannel[channel.id] ?? []).prefix(2)
        let widgetMessages = recentMessages.map { msg in
            ["sender": msg.senderName, "duration": msg.durationFormatted]
        }
        if let data = try? JSONEncoder().encode(widgetMessages) {
            defaults?.set(data, forKey: "widget_recentMessages")
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("[Notification] Error: \(error)") }
        }
    }

    private func sendLocalNotification(from senderName: String, durationMs: Int) {
        guard settings.notificationBanner else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = "Holler"
        content.body = "\(senderName) sent a \(durationMs / 1000)s voice message"
        if settings.notificationSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
