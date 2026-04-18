import Foundation
import WatchConnectivity
import Combine

/// Syncs settings from the paired iPhone via WatchConnectivity
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: WatchSettingsKey.displayName) }
    }
    @Published var roomCode: String {
        didSet { UserDefaults.standard.set(roomCode, forKey: WatchSettingsKey.roomCode) }
    }
    @Published var relayURL: String {
        didSet { UserDefaults.standard.set(relayURL, forKey: WatchSettingsKey.relayURL) }
    }
    @Published var deviceId: String {
        didSet { UserDefaults.standard.set(deviceId, forKey: WatchSettingsKey.deviceId) }
    }

    var isSetUp: Bool {
        !displayName.isEmpty && !roomCode.isEmpty && !relayURL.isEmpty
    }

    /// Fires when settings change so the app can reconnect
    let settingsChanged = PassthroughSubject<Void, Never>()

    override init() {
        let defaults = UserDefaults.standard
        self.displayName = defaults.string(forKey: WatchSettingsKey.displayName) ?? ""
        self.roomCode = defaults.string(forKey: WatchSettingsKey.roomCode) ?? ""
        self.relayURL = defaults.string(forKey: WatchSettingsKey.relayURL) ?? "wss://walkie-relay.up.railway.app"
        self.deviceId = defaults.string(forKey: WatchSettingsKey.deviceId) ?? UUID().uuidString

        super.init()

        // Persist deviceId on first launch
        if defaults.string(forKey: WatchSettingsKey.deviceId) == nil {
            defaults.set(deviceId, forKey: WatchSettingsKey.deviceId)
        }

        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            print("[Watch WC] WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("[Watch WC] Session activating...")
    }

    /// Manually update room code (e.g., from Watch text input)
    func updateRoomCode(_ code: String) {
        roomCode = code
        settingsChanged.send()
    }

    /// Manually update display name
    func updateDisplayName(_ name: String) {
        displayName = name
        settingsChanged.send()
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            print("[Watch WC] Activation error: \(error)")
        } else {
            print("[Watch WC] Activated: \(activationState.rawValue)")
        }
    }

    /// Receive application context from iPhone (persistent sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var changed = false

            if let name = applicationContext["displayName"] as? String, name != self.displayName {
                self.displayName = name
                changed = true
            }
            if let room = applicationContext["roomCode"] as? String, room != self.roomCode {
                self.roomCode = room
                changed = true
            }
            if let url = applicationContext["relayURL"] as? String, url != self.relayURL {
                self.relayURL = url
                changed = true
            }
            if let id = applicationContext["deviceId"] as? String, id != self.deviceId {
                self.deviceId = id
                changed = true
            }

            if changed {
                print("[Watch WC] Settings updated from iPhone")
                self.settingsChanged.send()
            }
        }
    }

    /// Receive immediate messages from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        session(session, didReceiveApplicationContext: message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        session(session, didReceiveApplicationContext: message)
        replyHandler(["status": "ok"])
    }

    /// Receive userInfo transfers
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        session(session, didReceiveApplicationContext: userInfo)
    }
}
