import SwiftUI

struct ChannelListView: View {
    var switchToTalk: (() -> Void)? = nil
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager

    @State private var showCreateChannel = false
    @State private var showJoinChannel = false
    @State private var channelToDelete: Channel?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(settings.channels) { channel in
                            ChannelCard(
                                channel: channel,
                                isActive: channel.id == settings.activeChannelID,
                                memberCount: connection.membersByChannel[channel.id]?.count ?? 0,
                                lastMessage: connection.messagesByChannel[channel.id]?.first
                            ) {
                                connection.switchChannel(to: channel)
                                switchToTalk?()
                            }
                            .contextMenu {
                                NavigationLink {
                                    ChannelDetailView(channel: channel)
                                } label: {
                                    Label("Channel Info", systemImage: "info.circle")
                                }

                                Button {
                                    shareChannel(channel)
                                } label: {
                                    Label("Share Invite", systemImage: "square.and.arrow.up")
                                }

                                if channel.mode != .home || settings.channels.count > 1 {
                                    Button(role: .destructive) {
                                        channelToDelete = channel
                                    } label: {
                                        Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Channels")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreateChannel = true
                        } label: {
                            Label("Create Channel", systemImage: "plus.circle")
                        }

                        Button {
                            showJoinChannel = true
                        } label: {
                            Label("Join Channel", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.hollerAccent)
                    }
                }
            }
            .sheet(isPresented: $showCreateChannel) {
                CreateChannelSheet()
            }
            .sheet(isPresented: $showJoinChannel) {
                JoinChannelSheet()
            }
            .alert("Leave Channel?", isPresented: Binding(
                get: { channelToDelete != nil },
                set: { if !$0 { channelToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { channelToDelete = nil }
                Button("Leave", role: .destructive) {
                    if let channel = channelToDelete {
                        settings.removeChannel(channel)
                    }
                    channelToDelete = nil
                }
            } message: {
                Text("You will no longer receive messages in this channel.")
            }
        }
    }

    private func shareChannel(_ channel: Channel) {
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

// MARK: - Create Channel Sheet

struct CreateChannelSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var groupNameInput = ""
    @State private var passphraseInput = ""
    @State private var isPassphraseVisible = false
    @State private var selectedMode: ChannelMode = .hangout
    @State private var selectedConnectionMode: ConnectionMode = .auto
    @State private var colorHex = "#FF6B47"

    private let colorOptions = ["#FF6B47", "#4ECDC4", "#FFE66D", "#A78BFA", "#60A5FA", "#F472B6", "#34D399"]

    private var wordCount: Int {
        passphraseWordCount(passphraseInput)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && wordCount >= 4
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHANNEL NAME")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            TextField("e.g. Road Trip 2026", text: $name)
                                .textFieldStyle(HollerTextFieldStyle())
                        }

                        // Group name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GROUP NAME")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            TextField("e.g. Wilson Family", text: $groupNameInput)
                                .textFieldStyle(HollerTextFieldStyle())
                                .autocorrectionDisabled()

                            Text("Optional. Share this with your group.")
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                        }

                        // Passphrase
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASSPHRASE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            HStack(spacing: 8) {
                                Group {
                                    if isPassphraseVisible {
                                        TextField("4+ words", text: $passphraseInput)
                                    } else {
                                        SecureField("4+ words", text: $passphraseInput)
                                    }
                                }
                                .textFieldStyle(HollerTextFieldStyle())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                                Button {
                                    isPassphraseVisible.toggle()
                                } label: {
                                    Image(systemName: isPassphraseVisible ? "eye.slash" : "eye")
                                        .foregroundStyle(Color.hollerTextSecondary)
                                        .frame(width: 44, height: 44)
                                }
                            }

                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: wordCount >= 4 ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                                    Text("\(wordCount) / 4 words")
                                        .font(.caption)
                                        .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                                }

                                Spacer()

                                Button {
                                    passphraseInput = generatePassphrase()
                                    isPassphraseVisible = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "dice")
                                        Text("Generate")
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.hollerAccent)
                                }
                            }

                            Text("Everyone in the group needs this passphrase to join.")
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                        }

                        // Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MODE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(ChannelMode.allCases) { mode in
                                        Button {
                                            selectedMode = mode
                                            colorHex = mode.defaultColorHex
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: mode.icon)
                                                Text(mode.displayName)
                                            }
                                            .font(.subheadline)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(selectedMode == mode ? Color(hex: mode.defaultColorHex) : Color.hollerCard)
                                            )
                                            .foregroundStyle(selectedMode == mode ? .white : Color.hollerTextSecondary)
                                        }
                                    }
                                }
                            }
                        }

                        // Color
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COLOR")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            HStack(spacing: 12) {
                                ForEach(colorOptions, id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(.white, lineWidth: hex == colorHex ? 3 : 0)
                                        )
                                        .onTapGesture { colorHex = hex }
                                }
                            }
                        }

                        // Connection Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CONNECTION")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.hollerTextSecondary)
                                .tracking(1)

                            Picker("Connection", selection: $selectedConnectionMode) {
                                ForEach(ConnectionMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(selectedConnectionMode.description)
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                        }

                        // Create button
                        Button {
                            let trimmedGroup = groupNameInput.trimmingCharacters(in: .whitespaces)
                            let trimmedPass = passphraseInput.trimmingCharacters(in: .whitespaces)
                            let code = Channel.roomCode(groupName: trimmedGroup, passphrase: trimmedPass)

                            let channel = Channel(
                                name: name.trimmingCharacters(in: .whitespaces),
                                code: code,
                                groupName: trimmedGroup,
                                passphrase: trimmedPass,
                                mode: selectedMode,
                                colorHex: colorHex,
                                connectionMode: selectedConnectionMode
                            )
                            settings.addChannel(channel)
                            connection.switchChannel(to: channel)
                            dismiss()
                        } label: {
                            Text("Create Channel")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(canCreate ? Color(hex: colorHex) : Color.hollerOffline)
                                )
                        }
                        .disabled(!canCreate)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Create Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.hollerTextSecondary)
                }
            }
        }
    }
}

// MARK: - Join Channel Sheet

struct JoinChannelSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var groupNameInput = ""
    @State private var passphraseInput = ""
    @State private var nickname = ""
    @State private var isPassphraseVisible = false
    @State private var selectedConnectionMode: ConnectionMode = .auto

    private var wordCount: Int {
        passphraseWordCount(passphraseInput)
    }

    private var canJoin: Bool {
        wordCount >= 4
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Group name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GROUP NAME")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        TextField("e.g. Wilson Family", text: $groupNameInput)
                            .textFieldStyle(HollerTextFieldStyle())
                            .autocorrectionDisabled()

                        Text("Leave empty if you were given only a passphrase.")
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }

                    // Passphrase
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASSPHRASE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        HStack(spacing: 8) {
                            Group {
                                if isPassphraseVisible {
                                    TextField("4+ words", text: $passphraseInput)
                                } else {
                                    SecureField("4+ words", text: $passphraseInput)
                                }
                            }
                            .textFieldStyle(HollerTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button {
                                isPassphraseVisible.toggle()
                            } label: {
                                Image(systemName: isPassphraseVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(Color.hollerTextSecondary)
                                    .frame(width: 44, height: 44)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: wordCount >= 4 ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                            Text("\(wordCount) / 4 words")
                                .font(.caption)
                                .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                        }
                    }

                    // Nickname
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHANNEL NICKNAME (optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        TextField("e.g. Road Trip", text: $nickname)
                            .textFieldStyle(HollerTextFieldStyle())
                    }

                    // Connection Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONNECTION")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        Picker("Connection", selection: $selectedConnectionMode) {
                            ForEach(ConnectionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(selectedConnectionMode.description)
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }

                    Button {
                        let trimmedGroup = groupNameInput.trimmingCharacters(in: .whitespaces)
                        let trimmedPass = passphraseInput.trimmingCharacters(in: .whitespaces)
                        let code = Channel.roomCode(groupName: trimmedGroup, passphrase: trimmedPass)

                        let channelName: String
                        if !nickname.trimmingCharacters(in: .whitespaces).isEmpty {
                            channelName = nickname.trimmingCharacters(in: .whitespaces)
                        } else if !trimmedGroup.isEmpty {
                            channelName = trimmedGroup
                        } else {
                            channelName = "Channel"
                        }

                        let channel = Channel(
                            name: channelName,
                            code: code,
                            groupName: trimmedGroup,
                            passphrase: trimmedPass,
                            mode: .custom,
                            connectionMode: selectedConnectionMode
                        )
                        settings.addChannel(channel)
                        connection.switchChannel(to: channel)
                        dismiss()
                    } label: {
                        Text("Join Channel")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(canJoin ? Color.hollerAccent : Color.hollerOffline)
                            )
                    }
                    .disabled(!canJoin)

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Join Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.hollerTextSecondary)
                }
            }
        }
    }
}

// MARK: - Holler Text Field Style

struct HollerTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.hollerCard)
            )
            .foregroundStyle(.white)
            .tint(Color.hollerAccent)
    }
}

#Preview {
    ChannelListView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ConnectionManager.shared)
        .preferredColorScheme(.dark)
}
