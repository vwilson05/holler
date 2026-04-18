import Foundation
import Speech
import AVFoundation

/// On-device speech transcription using SFSpeechRecognizer
final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()

    @Published var isAuthorized = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private init() {
        checkAuthorization()
    }

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
            }
        }
    }

    private func checkAuthorization() {
        isAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Transcribe audio data (AAC/M4A) and call completion with the result text
    func transcribe(audioData: Data, completion: @escaping (String) -> Void) {
        guard isAuthorized, let recognizer = speechRecognizer, recognizer.isAvailable else {
            return
        }

        // Write audio data to temp file for recognition
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe_\(UUID().uuidString).m4a")

        do {
            try audioData.write(to: tempURL)
        } catch {
            print("[Transcription] Failed to write temp file: \(error)")
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false

        if #available(iOS 16.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        recognizer.recognitionTask(with: request) { result, error in
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            if let error {
                print("[Transcription] Error: \(error.localizedDescription)")
                return
            }

            guard let result, result.isFinal else { return }

            let text = result.bestTranscription.formattedString
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }
}
