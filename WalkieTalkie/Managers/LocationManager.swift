import Foundation
import CoreLocation
import Combine

/// Manages location tracking for channel-based sharing
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isSharing = false

    private let locationManager = CLLocationManager()
    private var shareTimer: Timer?
    private var autoDisableTimer: Timer?

    /// 4 hours auto-disable
    private let autoDisableInterval: TimeInterval = 4 * 3600

    /// 30 second update interval
    private let shareInterval: TimeInterval = 30

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Start location updates just for displaying on the map (no relay to channel)
    func startUpdatingForMap() {
        locationManager.startUpdatingLocation()
    }

    func startSharing() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        locationManager.startUpdatingLocation()
        isSharing = true

        // Send location updates every 30s
        shareTimer = Timer.scheduledTimer(withTimeInterval: shareInterval, repeats: true) { [weak self] _ in
            self?.sendCurrentLocation()
        }

        // Auto-disable after 4 hours
        autoDisableTimer = Timer.scheduledTimer(withTimeInterval: autoDisableInterval, repeats: false) { [weak self] _ in
            self?.stopSharing()
            print("[Location] Auto-disabled after 4 hours")
        }

        // Send immediately
        sendCurrentLocation()

        print("[Location] Started sharing")
    }

    func stopSharing() {
        locationManager.stopUpdatingLocation()
        shareTimer?.invalidate()
        shareTimer = nil
        autoDisableTimer?.invalidate()
        autoDisableTimer = nil
        isSharing = false
        print("[Location] Stopped sharing")
    }

    private func sendCurrentLocation() {
        guard let location = locationManager.location else { return }
        currentLocation = location.coordinate

        ConnectionManager.shared.sendLocation(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] Error: \(error.localizedDescription)")
    }
}
