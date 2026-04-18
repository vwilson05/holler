import SwiftUI

/// Row displaying a channel member with online status and mute toggle
struct MemberRow: View {
    let member: Member
    var channelColor: Color = .hollerAccent
    var onToggleMute: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                Text(member.initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(member.isMuted ? Color.hollerOffline : channelColor)
                    )

                Circle()
                    .fill(member.isOnline ? Color.hollerOnline : Color.hollerOffline)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.hollerBackground, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }

            // Name and status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    if member.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }
                }

                Text(member.isOnline ? "Online" : member.lastActiveFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.hollerTextSecondary)
            }

            Spacer()

            // Haptic pattern indicator
            HStack(spacing: 4) {
                Image(systemName: "waveform.path")
                    .font(.caption2)
                Text(member.hapticPattern.displayName)
                    .font(.caption2)
            }
            .foregroundStyle(Color.hollerTextSecondary.opacity(0.6))

            // Mute button
            if let onToggleMute, member.id != AppSettings.shared.deviceID {
                Button {
                    onToggleMute()
                } label: {
                    Image(systemName: member.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(member.isMuted ? Color.hollerRecording : Color.hollerTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Color.hollerCard)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .background(Color.hollerCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
