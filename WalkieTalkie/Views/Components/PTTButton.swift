import SwiftUI

/// Large circular push-to-talk button with haptic feedback and visual states
struct PTTButton: View {
    var channelColor: Color = .hollerAccent

    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var connection: ConnectionManager

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var buttonColor: Color = .hollerAccent
    @State private var showSentFlash = false
    @State private var dragOffset: CGSize = .zero
    @State private var isCancelled = false

    private let buttonSize: CGFloat = 160
    private let cancelThreshold: CGFloat = 140  // horizontal distance to trigger cancel
    private let cancelReturnThreshold: CGFloat = 100  // must come back inside this to un-cancel (hysteresis)

    var body: some View {
        ZStack {
            // Outer pulse rings (visible when recording)
            if isPressed && !isCancelled {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.hollerRecording.opacity(0.15 - Double(i) * 0.04), lineWidth: 2)
                        .frame(
                            width: buttonSize + CGFloat(i) * 40 + 20,
                            height: buttonSize + CGFloat(i) * 40 + 20
                        )
                        .scaleEffect(pulseScale)
                }
            }

            // Main button — clean, sharp, no blur
            Circle()
                .fill(buttonColor)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    Circle()
                        .stroke(buttonColor.opacity(0.4), lineWidth: 3)
                        .frame(width: buttonSize + 8, height: buttonSize + 8)
                )
                .scaleEffect(isPressed ? 1.08 : 1.0)

            // Content
            VStack(spacing: 6) {
                if isCancelled {
                    Image(systemName: "xmark")
                        .font(.system(size: 36, weight: .medium))
                } else if isPressed {
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .medium))
                        .symbolEffect(.variableColor, isActive: true)

                    Text(String(format: "%.1fs", audio.recordingDuration))
                        .font(.caption.monospaced())
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 36, weight: .medium))
                }
            }
            .foregroundStyle(.white)

            // Cancel hint
            if isPressed && !isCancelled {
                VStack {
                    Spacer()
                    Text("Slide away to cancel")
                        .font(.caption)
                        .foregroundStyle(Color.hollerTextSecondary)
                        .offset(y: buttonSize / 2 + 24)
                }
            }
        }
        .offset(dragOffset)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed {
                        pressDown()
                    }

                    // Check for cancel gesture — horizontal only, with hysteresis
                    let horizontalDistance = abs(value.translation.width)

                    if !isCancelled && horizontalDistance > cancelThreshold {
                        isCancelled = true
                        buttonColor = Color.hollerOffline
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    } else if isCancelled && horizontalDistance < cancelReturnThreshold {
                        isCancelled = false
                        buttonColor = Color.hollerRecording
                    }

                    if isCancelled {
                        dragOffset = CGSize(
                            width: value.translation.width * 0.3,
                            height: 0
                        )
                    } else {
                        dragOffset = .zero
                    }
                }
                .onEnded { _ in
                    if isCancelled {
                        cancelRecording()
                    } else {
                        releaseUp()
                    }
                    dragOffset = .zero
                    isCancelled = false
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.interactiveSpring(), value: dragOffset)
        .onAppear {
            buttonColor = channelColor
        }
        .onChange(of: channelColor) { _, newColor in
            if !isPressed {
                buttonColor = newColor
            }
        }
    }

    // MARK: - Actions

    private func pressDown() {
        isPressed = true
        buttonColor = Color.hollerRecording

        HapticManager.shared.playRecordStart()
        audio.startRecording()

        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    private func releaseUp() {
        isPressed = false
        pulseScale = 1.0

        if let (data, durationMs) = audio.stopRecording() {
            // Flash green
            buttonColor = Color.hollerSent
            showSentFlash = true

            HapticManager.shared.playSent()
            connection.sendVoice(audioData: data, durationMs: durationMs)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    buttonColor = channelColor
                    showSentFlash = false
                }
            }
        } else {
            // Too short
            withAnimation {
                buttonColor = channelColor
            }
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }

    private func cancelRecording() {
        isPressed = false
        pulseScale = 1.0
        audio.cancelRecording()

        withAnimation(.easeOut(duration: 0.3)) {
            buttonColor = channelColor
        }
    }
}

#Preview {
    ZStack {
        Color.hollerBackground.ignoresSafeArea()
        PTTButton(channelColor: .hollerAccent)
    }
    .environmentObject(AudioManager.shared)
    .environmentObject(ConnectionManager.shared)
}
