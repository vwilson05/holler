import Foundation
import Combine

/// Handles WebSocket relay connection for internet communication using the wire protocol
final class WebSocketManager: NSObject, ObservableObject {
    static let shared = WebSocketManager()

    @Published var isConnected = false

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var isIntentionalDisconnect = false
    private var currentURL: String = ""
    private var currentRoom: String = ""
    private var currentMemberID: String = ""
    private var currentMemberName: String = ""

    var onMessageReceived: ((WireMessage) -> Void)?

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Connect / Disconnect

    func connect(url: String, room: String, memberID: String, memberName: String) {
        guard !url.isEmpty else {
            print("[WS] No relay URL configured, skipping")
            return
        }

        isIntentionalDisconnect = false
        currentURL = url
        currentRoom = room
        currentMemberID = memberID
        currentMemberName = memberName

        var urlString = url
        if !urlString.hasSuffix("/") { urlString += "/" }
        urlString += "ws?room=\(room)&id=\(memberID)&name=\(memberName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memberName)"

        guard let wsURL = URL(string: urlString) else {
            print("[WS] Invalid URL: \(urlString)")
            return
        }

        webSocket?.cancel(with: .goingAway, reason: nil)

        let task = urlSession.webSocketTask(with: wsURL)
        webSocket = task
        task.resume()
        listenForMessages()
        startPinging()

        print("[WS] Connecting to \(wsURL)")
    }

    func disconnect() {
        isIntentionalDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        print("[WS] Disconnected")
    }

    // MARK: - Send

    func send(_ wireMessage: WireMessage) {
        guard isConnected else { return }
        do {
            let jsonString = try wireMessage.encodedString()
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocket?.send(message) { error in
                if let error {
                    print("[WS] Send error: \(error)")
                }
            }
        } catch {
            print("[WS] Encoding error: \(error)")
        }
    }

    func sendRaw(_ data: Data) {
        guard isConnected else { return }
        webSocket?.send(.data(data)) { error in
            if let error {
                print("[WS] Send raw error: \(error)")
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
                    self.handleRawMessage(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleRawMessage(data)
                    }
                @unknown default:
                    break
                }
                self.listenForMessages()

            case .failure(let error):
                print("[WS] Receive error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleRawMessage(_ data: Data) {
        do {
            let wireMessage = try WireMessage.decode(from: data)
            DispatchQueue.main.async {
                self.onMessageReceived?(wireMessage)
            }
        } catch {
            // Try legacy format or server control messages
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                switch type {
                case "welcome", "peers":
                    print("[WS] Server control: \(type)")
                default:
                    print("[WS] Unknown server message: \(type)")
                }
            } else {
                print("[WS] Failed to decode message: \(error)")
            }
        }
    }

    // MARK: - Join/Leave

    func sendJoin(room: String, senderName: String, senderID: String) {
        let msg = WireMessage(
            type: .join,
            sender: senderName,
            senderID: senderID,
            room: room,
            payload: .empty
        )
        send(msg)
    }

    func sendLeave(room: String, senderName: String, senderID: String) {
        let msg = WireMessage(
            type: .leave,
            sender: senderName,
            senderID: senderID,
            room: room,
            payload: .empty
        )
        send(msg)
    }

    // MARK: - Ping / Reconnect

    private func startPinging() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let msg = WireMessage(
                type: .ping,
                sender: self.currentMemberName,
                senderID: self.currentMemberID,
                room: self.currentRoom,
                payload: .empty
            )
            self.send(msg)
        }
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self, !self.isConnected, !self.isIntentionalDisconnect else { return }
            self.connect(
                url: self.currentURL,
                room: self.currentRoom,
                memberID: self.currentMemberID,
                memberName: self.currentMemberName
            )
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            print("[WS] Connected")
            // Send join message
            self.sendJoin(room: self.currentRoom, senderName: self.currentMemberName, senderID: self.currentMemberID)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.scheduleReconnect()
            print("[WS] Closed: \(closeCode)")
        }
    }
}
