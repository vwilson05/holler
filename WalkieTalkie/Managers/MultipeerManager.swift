import Foundation
import MultipeerConnectivity

/// Handles LAN peer-to-peer communication via Multipeer Connectivity
final class MultipeerManager: NSObject, ObservableObject {
    static let shared = MultipeerManager()

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false

    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var currentRoomCode: String = ""
    private var currentServiceType: String = ""

    var onMessageReceived: ((WireMessage) -> Void)?

    override init() {
        super.init()
    }

    // MARK: - Start / Stop

    func start(displayName: String, roomCode: String) {
        stop()

        currentRoomCode = roomCode

        // Multipeer service type must be <= 15 chars, lowercase alphanumeric + hyphens
        // Use a hash of the room code to keep it short
        let sanitized = roomCode.lowercased().filter { $0.isLetter || $0.isNumber }
        currentServiceType = "hlr-\(String(sanitized.prefix(11)))"

        peerID = MCPeerID(displayName: displayName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        let discoveryInfo = ["room": roomCode]

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo,
            serviceType: currentServiceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        isAdvertising = true

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: currentServiceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        isBrowsing = true

        print("[Multipeer] Started: \(displayName), room: \(roomCode), service: \(currentServiceType)")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        isAdvertising = false
        isBrowsing = false
        connectedPeers = []
        print("[Multipeer] Stopped")
    }

    // MARK: - Send

    func send(_ wireMessage: WireMessage) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            let data = try wireMessage.encoded()
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("[Multipeer] Sent \(data.count) bytes to \(session.connectedPeers.count) peers")
        } catch {
            print("[Multipeer] Send error: \(error)")
        }
    }

    func sendRaw(_ data: Data) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[Multipeer] Send raw error: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                print("[Multipeer] Connected: \(peerID.displayName)")
            case .connecting:
                print("[Multipeer] Connecting: \(peerID.displayName)")
            case .notConnected:
                print("[Multipeer] Disconnected: \(peerID.displayName)")
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let wireMessage = try WireMessage.decode(from: data)
            DispatchQueue.main.async {
                self.onMessageReceived?(wireMessage)
            }
        } catch {
            print("[Multipeer] Failed to decode message from \(peerID.displayName): \(error)")
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from peers in the same room
        invitationHandler(true, session)
        print("[Multipeer] Accepted invitation from \(peerID.displayName)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[Multipeer] Advertiser error: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["room"] == currentRoomCode else {
            print("[Multipeer] Ignoring peer \(peerID.displayName) - different room")
            return
        }

        guard peerID.displayName != self.peerID.displayName else { return }

        print("[Multipeer] Found peer: \(peerID.displayName), inviting...")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Multipeer] Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[Multipeer] Browser error: \(error)")
    }
}
