import SwiftUI

/// Card displaying a channel with its mode, member count, and last message
struct ChannelCard: View {
    let channel: Channel
    let isActive: Bool
    let memberCount: Int
    let lastMessage: VoiceMessage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Channel icon
                Image(systemName: channel.mode.icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: channel.colorHex))
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: channel.colorHex).opacity(0.15))
                    )

                // Channel info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.name)
                            .font(.headline)
                            .foregroundStyle(Color.hollerTextPrimary)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: channel.colorHex))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: channel.colorHex).opacity(0.2))
                                )
                        }
                    }

                    HStack(spacing: 12) {
                        // Member count
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                            Text("\(memberCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.hollerTextSecondary)

                        // Last message
                        if let msg = lastMessage {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.caption2)
                                Text("\(msg.senderName) - \(msg.durationFormatted)")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.hollerTextSecondary)
                        }
                    }
                }

                Spacer()

                // Room code preview (first 6 chars for verification)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(channel.code.prefix(6)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.hollerTextSecondary.opacity(0.5))

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.hollerTextSecondary.opacity(0.3))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.hollerCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isActive ? Color(hex: channel.colorHex).opacity(0.4) : .clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
