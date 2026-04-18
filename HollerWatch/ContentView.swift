import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var ws = WatchWebSocketManager.shared
    @StateObject private var audio = WatchAudioManager.shared

    @State private var isPressing = false
    @State private var showMembers = false
    @State private var showSettings = false
    @State private var crownValue: Double = 0.5

    // Seen message IDs for dedup
    @State private var seenIds = Set<String>()

    var body: some View {
        if connectivity.isSetUp {
            mainView
                .onAppear { connectIfNeeded() }
                .onChange(of: connectivity.roomCode) { connectIfNeeded() }
                .onReceive(connectivity.settingsChanged) { connectIfNeeded() }
        } else {
            setupView
        }
    }

    // MARK: - Main PTT View

    private var mainView: some View {
        NavigationStack {
            VStack(spacing: 4) {
                // Channel + status header
                headerView

                Spacer()

                // PTT button
                pttButton

                Spacer()

                // Last message / replay
                lastMessageView
            }
            .padding(.horizontal, 4)
            .focusable()
            .digitalCrownRotation($crownValue, from: 0, through: 1, sensitivity: .low)
            .onChange(of: crownValue) { newVal in
                audio.adjustVolume(by: (newVal - 0.5) * 0.1)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showMembers = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                            Text("\(ws.peerCount)")
                                .font(.caption2)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption2)
                    }
                }
            }
            .sheet(isPresented: $showMembers) {
                MemberListView()
            }
            .sheet(isPresented: $showSettings) {
                watchSettingsView
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
            // Connection dot
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            Text(connectivity.roomCode)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            if audio.isPlaying, let sender = audio.currentPlaybackSender {
                HStack(spacing: 2) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor)
                        .font(.caption2)
                    Text(sender)
                        .font(.caption2)
                }
                .foregroundStyle(.green)
            }
        }
    }

    private var connectionColor: Color {
        switch ws.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        }
    }

    // MARK: - PTT Button

    private var pttButton: some View {
        let buttonColor: Color = {
            if audio.isRecording { return .red }
            if isPressing { return .red.opacity(0.8) }
            return .blue
        }()

        return ZStack {
            Circle()
                .fill(buttonColor.gradient)
                .frame(width: 110, height: 110)
                .shadow(color: buttonColor.opacity(0.4), radius: audio.isRecording ? 15 : 5)

            VStack(spacing: 4) {
                Image(systemName: audio.isRecording ? "waveform" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor, isActive: audio.isRecording)

                if audio.isRecording {
                    Text(String(format: "%.1fs", audio.recordingDuration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .scaleEffect(isPressing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing {
                        isPressing = true
                        audio.startRecording()
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    sendRecording()
                }
        )
    }

    // MARK: - Last Message

    private var lastMessageView: some View {
        Group {
            if let sender = audio.lastReceivedSender {
                Button {
                    audio.replayLast()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                        Text(sender)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            } else {
                Text("Hold to talk")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Holler")
                .font(.headline)

            Text("Open the iPhone app to sync settings, or enter a room code below.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Enter Room Code") {
                showSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showSettings) {
            watchSettingsView
        }
    }

    // MARK: - Watch Settings

    private var watchSettingsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Your name", text: Binding(
                        get: { connectivity.displayName },
                        set: { connectivity.updateDisplayName($0) }
                    ))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Room Code")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Room code", text: Binding(
                        get: { connectivity.roomCode },
                        set: { connectivity.updateRoomCode($0) }
                    ))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 8, height: 8)
                        Text(connectionStatusText)
                            .font(.caption2)
                    }
                }

                if ws.isConnected {
                    Button("Disconnect", role: .destructive) {
                        ws.disconnect()
                    }
                } else {
                    Button("Connect") {
                        connectIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private var connectionStatusText: String {
        switch ws.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: - Actions

    private func connectIfNeeded() {
        guard connectivity.isSetUp else { return }

        // Wire up voice callback
        ws.onVoiceReceived = { [self] voiceMsg in
            guard voiceMsg.senderId != connectivity.deviceId else { return }
            guard !seenIds.contains(voiceMsg.id) else { return }
            seenIds.insert(voiceMsg.id)

            // Trim seen IDs
            if seenIds.count > 200 {
                seenIds.removeAll()
            }

            audio.enqueueAndPlay(voiceMsg)
        }

        ws.connect(
            url: connectivity.relayURL,
            roomCode: connectivity.roomCode,
            memberId: connectivity.deviceId,
            memberName: connectivity.displayName
        )
    }

    private func sendRecording() {
        guard let (data, duration) = audio.stopRecording() else { return }

        let message = VoiceMessage(
            senderId: connectivity.deviceId,
            senderName: connectivity.displayName,
            duration: duration,
            audioData: data
        )

        guard let encoded = try? JSONEncoder().encode(WireMessage.voice(message)) else {
            print("[Watch] Failed to encode voice message")
            return
        }

        ws.send(encoded)
        print("[Watch] Sent voice: \(String(format: "%.1f", duration))s, \(encoded.count) bytes")
    }
}

#Preview {
    ContentView()
}
