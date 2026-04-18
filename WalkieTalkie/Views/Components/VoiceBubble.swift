import SwiftUI

/// Voice message bubble with waveform, transcription, and tap-to-replay
struct VoiceBubble: View {
    let message: VoiceMessage
    var channelColor: Color = .hollerAccent

    @EnvironmentObject var audio: AudioManager

    private var isOwnMessage: Bool { message.isFromCurrentUser }
    private var isCurrentlyPlaying: Bool { audio.currentPlaybackMessageID == message.id }

    var body: some View {
        HStack {
            if isOwnMessage { Spacer(minLength: 60) }

            HStack(spacing: 10) {
                if !isOwnMessage {
                    avatar
                }

                VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                    if !isOwnMessage {
                        Text(message.senderName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                    }

                    // Voice message content
                    Button {
                        audio.playMessage(message)
                    } label: {
                        HStack(spacing: 8) {
                            // Play/pause icon
                            Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(isOwnMessage ? .white.opacity(0.9) : channelColor)
                                .frame(width: 20)

                            // Waveform
                            waveform

                            // Duration
                            Text(message.durationFormatted)
                                .font(.caption2.monospaced())
                                .foregroundStyle(isOwnMessage ? .white.opacity(0.6) : Color.hollerTextSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isOwnMessage ? channelColor.opacity(0.3) : Color.hollerCard)
                        )
                    }

                    // Transcription
                    if let transcription = message.transcription, !transcription.isEmpty {
                        Text(transcription)
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                            .lineLimit(3)
                            .padding(.horizontal, 4)
                    }

                    // Timestamp
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(Color.hollerTextSecondary.opacity(0.5))
                }

                if isOwnMessage {
                    avatar
                }
            }

            if !isOwnMessage { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Avatar

    private var avatar: some View {
        Text(senderInitials)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(avatarColor)
            )
    }

    // MARK: - Waveform

    private var waveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isCurrentlyPlaying
                          ? (isOwnMessage ? Color.white.opacity(0.9) : channelColor)
                          : (isOwnMessage ? Color.white.opacity(0.4) : Color.hollerTextSecondary.opacity(0.4)))
                    .frame(width: 2, height: waveformHeight(for: i))
            }
        }
        .frame(height: 20)
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        // Deterministic pseudo-random heights based on message ID
        let seed = message.id.hashValue &+ index
        let normalized = abs(Double(seed % 100)) / 100.0
        return 4 + normalized * 16
    }

    // MARK: - Helpers

    private var senderInitials: String {
        let parts = message.senderName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(message.senderName.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let hash = abs(message.senderName.hashValue)
        let colors: [Color] = [
            .hollerAccent,
            Color(hex: "#4ECDC4"),
            Color(hex: "#A78BFA"),
            Color(hex: "#F472B6"),
            Color(hex: "#60A5FA"),
        ]
        return colors[hash % colors.count]
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
