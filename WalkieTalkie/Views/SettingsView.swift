import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager

    @State private var nameInput = ""
    @State private var relayInput = ""
    @State private var groupNameInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Profile
                        settingsSection(title: "Profile") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 16) {
                                    Text(initials)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 56, height: 56)
                                        .background(Circle().fill(Color.hollerAccent))

                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("Display Name", text: $nameInput)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                            .onSubmit { saveName() }

                                        Text("ID: \(String(settings.deviceID.prefix(8)))...")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Color.hollerTextSecondary)
                                    }
                                }

                                if nameInput != settings.displayName && !nameInput.isEmpty {
                                    Button("Save Name") { saveName() }
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.hollerAccent)
                                }
                            }
                            .padding(16)
                            .hollerCard()
                        }

                        // Group Name
                        settingsSection(title: "Group") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Group name", text: $groupNameInput)
                                    .textFieldStyle(HollerTextFieldStyle())
                                    .autocorrectionDisabled()
                                    .onSubmit { saveGroupName() }

                                if groupNameInput != settings.groupName {
                                    Button("Save Group Name") { saveGroupName() }
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.hollerAccent)
                                }

                                Text("Used with a passphrase to generate channel room codes.")
                                    .font(.caption)
                                    .foregroundStyle(Color.hollerTextSecondary)
                            }
                        }

                        // Relay Server
                        settingsSection(title: "Relay Server") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("wss://your-server.example.com", text: $relayInput)
                                    .textFieldStyle(HollerTextFieldStyle())
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .onSubmit { saveRelay() }

                                HStack {
                                    Circle()
                                        .fill(connection.wsConnected ? Color.hollerOnline : Color.hollerOffline)
                                        .frame(width: 8, height: 8)

                                    Text(connection.wsConnected ? "Connected" : (settings.relayServerURL.isEmpty ? "LAN only" : "Disconnected"))
                                        .font(.caption)
                                        .foregroundStyle(Color.hollerTextSecondary)

                                    Spacer()

                                    if relayInput != settings.relayServerURL {
                                        Button("Save") { saveRelay() }
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(Color.hollerAccent)
                                    }
                                }

                                Text("Leave empty for LAN-only mode. Deploy the included server for internet relay.")
                                    .font(.caption)
                                    .foregroundStyle(Color.hollerTextSecondary)

                                Text("Connection mode (LAN / Relay / Auto) is set per channel in channel settings.")
                                    .font(.caption)
                                    .foregroundStyle(Color.hollerTextSecondary)
                            }
                        }

                        // Notifications
                        settingsSection(title: "Notifications") {
                            VStack(spacing: 0) {
                                settingsToggle(icon: "speaker.wave.2.fill", title: "Sound", isOn: $settings.notificationSound)
                                Divider().background(Color.hollerTextSecondary.opacity(0.2))
                                settingsToggle(icon: "iphone.radiowaves.left.and.right", title: "Haptic", isOn: $settings.notificationHaptic)
                                Divider().background(Color.hollerTextSecondary.opacity(0.2))
                                settingsToggle(icon: "bell.fill", title: "Banner", isOn: $settings.notificationBanner)
                            }
                            .hollerCard()
                        }

                        // Background Behavior
                        settingsSection(title: "Background") {
                            VStack(spacing: 0) {
                                settingsToggle(icon: "bolt.fill", title: "Stay active in background", isOn: $settings.stayActiveInBackground)
                            }
                            .hollerCard()

                            Text(settings.stayActiveInBackground
                                ? "Messages auto-play even when the app is minimized. Uses slightly more battery."
                                : "Messages arrive as notifications when the app is minimized. Better battery life.")
                                .font(.caption)
                                .foregroundStyle(Color.hollerTextSecondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 6)
                        }

                        // Audio Quality
                        settingsSection(title: "Audio Quality") {
                            VStack(spacing: 0) {
                                ForEach(AudioQuality.allCases) { quality in
                                    Button {
                                        settings.audioQuality = quality
                                    } label: {
                                        HStack {
                                            Text(quality.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if settings.audioQuality == quality {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Color.hollerAccent)
                                            }
                                        }
                                        .padding(14)
                                    }

                                    if quality != AudioQuality.allCases.last {
                                        Divider().background(Color.hollerTextSecondary.opacity(0.2))
                                    }
                                }
                            }
                            .hollerCard()
                        }

                        // Haptic Identity
                        settingsSection(title: "Haptic Identity") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Each member has a unique haptic pattern that plays before their voice messages.")
                                    .font(.caption)
                                    .foregroundStyle(Color.hollerTextSecondary)

                                ForEach(HapticPattern.allCases) { pattern in
                                    Button {
                                        HapticManager.shared.previewPattern(pattern)
                                    } label: {
                                        HStack {
                                            Image(systemName: "waveform.path")
                                                .foregroundStyle(Color.hollerAccent)
                                            Text(pattern.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text("Tap to preview")
                                                .font(.caption)
                                                .foregroundStyle(Color.hollerTextSecondary)
                                        }
                                        .padding(12)
                                    }

                                    if pattern != HapticPattern.allCases.last {
                                        Divider().background(Color.hollerTextSecondary.opacity(0.2))
                                    }
                                }
                            }
                            .hollerCard()
                        }

                        // Theme
                        settingsSection(title: "Appearance") {
                            settingsToggle(icon: "moon.fill", title: "Dark Mode", isOn: $settings.prefersDarkMode)
                                .hollerCard()
                        }

                        // App Info
                        settingsSection(title: "About") {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Version")
                                        .foregroundStyle(Color.hollerTextSecondary)
                                    Spacer()
                                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                        .foregroundStyle(.white)
                                }
                                .font(.subheadline)
                            }
                            .padding(14)
                            .hollerCard()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                nameInput = settings.displayName
                relayInput = settings.relayServerURL
                groupNameInput = settings.groupName
            }
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = nameInput.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(nameInput.prefix(2)).uppercased()
    }

    private func saveName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.displayName = trimmed
    }

    private func saveGroupName() {
        settings.groupName = groupNameInput.trimmingCharacters(in: .whitespaces)
    }

    private func saveRelay() {
        settings.relayServerURL = relayInput.trimmingCharacters(in: .whitespaces)
        connection.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            connection.start()
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.hollerTextSecondary)
                .tracking(1)

            content()
        }
    }

    private func settingsToggle(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.hollerAccent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Color.hollerAccent)
                .labelsHidden()
        }
        .padding(14)
    }
}

// MARK: - Passphrase Word List

let passphraseWordList: [String] = [
    "alpine","amber","anchor","arrow","autumn","beacon","blaze","bloom","breeze","bridge",
    "canyon","cedar","chase","cliff","cloud","cobalt","coral","crest","crystal","cypress",
    "dawn","delta","drift","dusk","eagle","ember","falcon","fern","flint","forge",
    "frost","gale","glacier","grove","harbor","hawk","haven","horizon","indigo","iron",
    "jade","jasper","jubilee","kelp","lantern","lark","lava","lunar","maple","marble",
    "meadow","mesa","mist","moss","nebula","north","nova","oasis","oak","ocean",
    "olive","onyx","orbit","otter","palm","pearl","pine","plume","prism","pulse",
    "quartz","rain","rapids","raven","reef","ridge","river","robin","ruby","sage",
    "sand","sequoia","shadow","sierra","silver","slate","solar","spark","spruce","star",
    "stone","storm","summit","swift","thorn","thunder","timber","trail","tulip","tundra",
    "valley","velvet","venture","violet","vista","walnut","wave","willow","wind","winter",
    "wolf","wren","zenith","zephyr"
]

func generatePassphrase(wordCount: Int = 4) -> String {
    var words: [String] = []
    for _ in 0..<wordCount {
        if let word = passphraseWordList.randomElement() {
            words.append(word)
        }
    }
    return words.joined(separator: " ")
}

func passphraseWordCount(_ passphrase: String) -> Int {
    passphrase.trimmingCharacters(in: .whitespaces)
        .split(separator: " ")
        .filter { !$0.isEmpty }
        .count
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager

    @State private var nameInput = ""
    @State private var groupNameInput = ""
    @State private var passphraseInput = ""
    @State private var isPassphraseVisible = false

    private var wordCount: Int {
        passphraseWordCount(passphraseInput)
    }

    private var canConnect: Bool {
        let trimmedName = nameInput.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty && wordCount >= 4
    }

    var body: some View {
        ZStack {
            Color.hollerBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.hollerAccent)

                Text("Holler")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Voice messaging for your crew")
                    .font(.subheadline)
                    .foregroundStyle(Color.hollerTextSecondary)

                Spacer()

                VStack(spacing: 20) {
                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT SHOULD WE CALL YOU?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        TextField("Your name", text: $nameInput)
                            .textFieldStyle(HollerTextFieldStyle())
                            .autocorrectionDisabled()
                            .font(.title3)
                    }

                    // Group name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GROUP NAME")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.hollerTextSecondary)
                            .tracking(1)

                        TextField("e.g. Wilson Family", text: $groupNameInput)
                            .textFieldStyle(HollerTextFieldStyle())
                            .autocorrectionDisabled()

                        Text("Optional. Combined with passphrase to create your room.")
                            .font(.caption)
                            .foregroundStyle(Color.hollerTextSecondary)
                    }

                    // Passphrase input
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
                            // Word count indicator
                            HStack(spacing: 4) {
                                Image(systemName: wordCount >= 4 ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                                Text("\(wordCount) / 4 words")
                                    .font(.caption)
                                    .foregroundStyle(wordCount >= 4 ? Color.hollerOnline : Color.hollerTextSecondary)
                            }

                            Spacer()

                            // Generate button
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
                    }
                }
                .padding(.horizontal, 24)

                // Connect button
                Button {
                    let trimmedName = nameInput.trimmingCharacters(in: .whitespaces)
                    guard !trimmedName.isEmpty, wordCount >= 4 else { return }

                    settings.displayName = trimmedName
                    settings.groupName = groupNameInput.trimmingCharacters(in: .whitespaces)

                    // Create home channel with passphrase-derived room code
                    let code = Channel.roomCode(
                        groupName: settings.groupName,
                        passphrase: passphraseInput.trimmingCharacters(in: .whitespaces)
                    )
                    let homeChannel = Channel(
                        name: settings.groupName.isEmpty ? "Home" : settings.groupName,
                        code: code,
                        groupName: settings.groupName,
                        passphrase: passphraseInput.trimmingCharacters(in: .whitespaces),
                        mode: .home,
                        colorHex: ChannelMode.home.defaultColorHex
                    )
                    settings.channels = [homeChannel]
                    settings.activeChannelID = homeChannel.id

                    // Request permissions
                    TranscriptionManager.shared.requestPermission()

                    connection.start()
                } label: {
                    Text("Connect")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canConnect ? Color.hollerAccent : Color.hollerOffline)
                        )
                }
                .disabled(!canConnect)
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 60)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ConnectionManager.shared)
        .preferredColorScheme(.dark)
}
