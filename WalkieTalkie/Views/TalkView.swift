import SwiftUI

/// The main push-to-talk screen with channel header, messages, and PTT button
struct TalkView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @EnvironmentObject var audio: AudioManager

    @State private var searchText = ""
    @State private var showAloneWarning = false
    @State private var aloneCheckTask: Task<Void, Never>?

    var channelColor: Color {
        Color(hex: settings.activeChannel?.colorHex ?? "#FF6B47")
    }

    var filteredMessages: [VoiceMessage] {
        if searchText.isEmpty {
            return connection.activeChannelMessages
        }
        return connection.searchMessages(query: searchText, in: settings.activeChannelID ?? UUID())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Channel selector (horizontal scroll)
                    channelScroller
                        .padding(.top, 8)

                    // Status bar
                    statusBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Alone in room warning
                    if showAloneWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "person.slash.fill")
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                            Text("No one else is here yet. Make sure your group name and passphrase match exactly.")
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.hollerCard)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.opacity)
                    }

                    // Playback indicator (top, visible banner)
                    if audio.isPlaying, let sender = audio.playbackSender {
                        playbackIndicator(sender: sender)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }

                    // Search bar
                    if !connection.activeChannelMessages.isEmpty {
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    // Messages list
                    messagesList
                        .padding(.top, 8)

                    Spacer()

                    // PTT Button
                    PTTButton(channelColor: channelColor)
                        .padding(.bottom, 12)

                    // Hint text
                    Text(audio.isRecording ? "" : "Hold to talk")
                        .font(.subheadline)
                        .foregroundStyle(Color.hollerTextSecondary)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { startAloneCheck() }
            .onChange(of: settings.activeChannelID) { _, _ in startAloneCheck() }
            .onChange(of: connection.activeChannelMembers.count) { _, newCount in
                if newCount > 1 {
                    withAnimation { showAloneWarning = false }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Holler")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.hollerTextPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Alone Check

    private func startAloneCheck() {
        aloneCheckTask?.cancel()
        showAloneWarning = false
        aloneCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            let otherMembers = connection.activeChannelMembers.filter { $0.id != settings.deviceID }
            if otherMembers.isEmpty {
                withAnimation { showAloneWarning = true }
            }
        }
    }

    // MARK: - Channel Scroller

    private var channelScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(settings.channels) { channel in
                    ChannelPill(
                        channel: channel,
                        isActive: channel.id == settings.activeChannelID
                    ) {
                        if channel.id != settings.activeChannelID {
                            connection.switchChannel(to: channel)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connection.lanPeerCount > 0 ? Color.hollerOnline : Color.hollerOffline)
                    .frame(width: 8, height: 8)
                Text("LAN: \(connection.lanPeerCount)")
                    .font(.caption)
                    .foregroundStyle(Color.hollerTextSecondary)
            }

            if !settings.relayServerURL.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connection.wsConnected ? Color.hollerReceived : Color.hollerOffline)
                        .frame(width: 8, height: 8)
                    Text("Relay")
                        .font(.caption)
                        .foregroundStyle(Color.hollerTextSecondary)
                }
            }

            Spacer()

            if let channel = settings.activeChannel {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text(String(channel.code.prefix(6)))
                        .font(.caption.monospaced())
                }
                .foregroundStyle(Color.hollerTextSecondary.opacity(0.6))
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.hollerTextSecondary)
                .font(.subheadline)

            TextField("Search messages...", text: $searchText)
                .foregroundStyle(Color.hollerTextPrimary)
                .font(.subheadline)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.hollerCard)
        )
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredMessages) { msg in
                        VoiceBubble(
                            message: msg,
                            channelColor: channelColor
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 320)
            .onChange(of: filteredMessages.count) { _, _ in
                if let last = filteredMessages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Playback

    private func playbackIndicator(sender: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.subheadline)
                .symbolEffect(.variableColor)
                .foregroundStyle(channelColor)

            Text("Listening to \(sender)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.hollerTextPrimary)

            Spacer()

            Button {
                audio.stopPlayback()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.hollerTextSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.hollerCardElevated)
        )
    }
}

// MARK: - Channel Pill

struct ChannelPill: View {
    let channel: Channel
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: channel.mode.icon)
                    .font(.caption2)
                Text(channel.name)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? Color(hex: channel.colorHex) : Color.hollerCard)
            )
            .foregroundStyle(isActive ? .white : Color.hollerTextSecondary)
        }
    }
}

#Preview {
    TalkView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ConnectionManager.shared)
        .environmentObject(AudioManager.shared)
        .preferredColorScheme(.dark)
}
