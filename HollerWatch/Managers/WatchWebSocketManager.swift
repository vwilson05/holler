import Foundation
import Combine

/// Direct WebSocket connection from Watch for independent operation
class WatchWebSocketManager: NSObject, ObservableObject {
    static let shared = WatchWebSocketManager()

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var peerCount: Int = 0
    @Published var members: [Member] = []

    var isConnected: Bool { connectionState == .connected }

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var isIntentionalDisconnect = false

    var onVoiceReceived: ((VoiceMessage) -> Void)?

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Connect / Disconnect

    func connect(url: String, roomCode: String, memberId: String, memberName: String) {
        guard !url.isEmpty, !roomCode.isEmpty else { return }

        isIntentionalDisconnect = false
        connectionState = .connecting

        var urlString = url
        if !urlString.hasSuffix("/") { urlString += "/" }

        let encodedName = memberName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memberName
        urlString += "ws?room=\(roomCode)&id=\(memberId)&name=\(encodedName)"

        guard let wsURL = URL(string: urlString) else {
            print("[Watch WS] Invalid URL: \(urlString)")
            connectionState = .disconnected
            return
        }

        webSocket?.cancel(with: .goingAway, reason: nil)

        let task = urlSession.webSocketTask(with: wsURL)
        webSocket = task
        task.resume()
        listenForMessages()
        startPinging()

        print("[Watch WS] Connecting to \(wsURL)")
    }

    func disconnect() {
        isIntentionalDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionState = .disconnected
        peerCount = 0
        members = []
        print("[Watch WS] Disconnected")
    }

    // MARK: - Send

    func send(_ data: Data) {
        guard isConnected else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocket?.send(message) { error in
            if let error {
                print("[Watch WS] Send error: \(error)")
            }
        }
    }

    // MARK: - Receive Loop

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleMessage(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleMessage(data)
                    }
                @unknown default:
                    break
                }
                self.listenForMessages()

            case .failure(let error):
                print("[Watch WS] Receive error: \(error)")
                DispatchQueue.main.async {
                    self.connectionState = .disconnected
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        // Check for server control messages
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            switch type {
            case "peers":
                if let count = json["count"] as? Int {
                    DispatchQueue.main.async {
                        self.peerCount = count
                    }
                }
            case "members":
                if let memberList = json["members"] as? [[String: Any]] {
                    DispatchQueue.main.async {
                        self.members = memberList.compactMap { dict in
                            guard let id = dict["id"] as? String,
                                  let name = dict["name"] as? String else { return nil }
                            return Member(id: id, name: name, isOnline: true)
                        }
                        self.peerCount = self.members.count
                    }
                }
            case "welcome":
                print("[Watch WS] Server welcome received")
            default:
                break
            }
            return
        }

        // Decode wire message
        guard let wireMessage = try? JSONDecoder().decode(WireMessage.self, from: data) else {
            return
        }

        switch wireMessage {
        case .voice(let voiceMsg):
            DispatchQueue.main.async {
                self.onVoiceReceived?(voiceMsg)
            }
        case .presence(let update):
            DispatchQueue.main.async {
                if update.isOnline {
                    if !self.members.contains(where: { $0.id == update.memberId }) {
                        self.members.append(Member(id: update.memberId, name: update.memberName, isOnline: true))
                    }
                } else {
                    self.members.removeAll { $0.id == update.memberId }
                }
                self.peerCount = self.members.count
            }
        case .ping:
            break
        }
    }

    // MARK: - Ping / Reconnect

    private func startPinging() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.webSocket?.sendPing { error in
                if let error {
                    print("[Watch WS] Ping error: \(error)")
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, !self.isConnected, !self.isIntentionalDisconnect else { return }
            let defaults = UserDefaults.standard
            let url = defaults.string(forKey: WatchSettingsKey.relayURL) ?? ""
            let room = defaults.string(forKey: WatchSettingsKey.roomCode) ?? ""
            let id = defaults.string(forKey: WatchSettingsKey.deviceId) ?? ""
            let name = defaults.string(forKey: WatchSettingsKey.displayName) ?? ""
            self.connect(url: url, roomCode: room, memberId: id, memberName: name)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WatchWebSocketManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.connectionState = .connected
            print("[Watch WS] Connected")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.scheduleReconnect()
            print("[Watch WS] Closed: \(closeCode)")
        }
    }
}
