import SwiftUI

/// Shows channel info with member list and management
struct ChannelDetailView: View {
    let channel: Channel

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.dismiss) var dismiss

    var members: [Member] {
        connection.membersByChannel[channel.id] ?? []
    }

    var body: some View {
        ZStack {
            Color.hollerBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Channel info header
                    VStack(spacing: 12) {
                        Image(systemName: channel.mode.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(Color(hex: channel.colorHex))

                        Text(channel.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        if !channel.groupName.isEmpty {
                            Text(channel.groupName)
                                .font(.headline)
                                .foregroundStyle(Color.hollerTextSecondary)
                        }

                        Text(channel.mode.displayName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(hex: channel.colorHex).opacity(0.2)))
                            .foregroundStyle(Color(hex: channel.colorHex))
                    }
                    .padding(.top, 16)

                    // Connection Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONNECTION MODE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        Picker("Connection", selection: Binding(
                            get: { channel.connectionMode },
                            set: { newMode in
                                var updated = channel
                                updated.connectionMode = newMode
                                settings.activeChannel = updated
                                // Restart connection with new mode
                                connection.switchChannel(to: updated)
                            }
                        )) {
                            ForEach(ConnectionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(channel.connectionMode.description)
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }
                    .padding(.horizontal, 16)

                    // Location sharing toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOCATION SHARING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(Color.hollerAccent)

                            Toggle("Share my location", isOn: Binding(
                                get: { channel.isLocationSharingActive },
                                set: { enabled in
                                    var updated = channel
                                    updated.locationSharingEnabled = enabled
                                    if enabled {
                                        updated.locationSharingExpiry = Date().addingTimeInterval(4 * 3600)
                                        LocationManager.shared.startSharing()
                                    } else {
                                        updated.locationSharingExpiry = nil
                                        LocationManager.shared.stopSharing()
                                    }
                                    settings.activeChannel = updated
                                }
                            ))
                            .tint(Color.hollerAccent)
                        }
                        .padding(14)
                        .hollerCard()

                        Text("Auto-disables after 4 hours. Requires location permission.")
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }
                    .padding(.horizontal, 16)

                    // Members
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MEMBERS (\(members.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            Spacer()

                            Button {
                                shareInvite()
                            } label: {
                                Label("Invite", systemImage: "person.badge.plus")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.hollerAccent)
                            }
                        }

                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                channelColor: Color(hex: channel.colorHex),
                                onToggleMute: {
                                    connection.toggleMute(memberID: member.id, channelID: channel.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // Invite section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INVITE LINK")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        Button {
                            shareInvite()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Channel Code")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .hollerCard()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shareInvite() {
        let groupEncoded = channel.groupName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let passEncoded = channel.passphrase.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = "https://holler-relay-production.up.railway.app/?g=\(groupEncoded)&p=\(passEncoded)"
        let text = "Join my Holler channel \"\(channel.name)\"!\n\(url)"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
