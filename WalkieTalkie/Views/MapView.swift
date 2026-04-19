import SwiftUI
import MapKit

/// Map view showing channel members' live locations
struct MapTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @StateObject private var locationManager = LocationManager.shared

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedMemberID: String?

    var activeChannel: Channel? { settings.activeChannel }

    var memberAnnotations: [MemberAnnotation] {
        guard let channelID = settings.activeChannelID else { return [] }
        let members = connection.membersByChannel[channelID] ?? []

        var annotations = members.compactMap { member -> MemberAnnotation? in
            guard let loc = connection.memberLocations[member.id] else { return nil }
            let lastMessage = connection.messagesByChannel[channelID]?.first(where: { $0.senderID == member.id })
            return MemberAnnotation(
                id: member.id,
                name: member.name,
                initials: member.initials,
                coordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lng),
                lastMessagePreview: lastMessage?.transcription ?? lastMessage?.durationFormatted,
                isOnline: member.isOnline
            )
        }

        // Always show self from live CLLocation (more responsive than waiting for relay round-trip)
        if let myLoc = locationManager.currentLocation,
           !annotations.contains(where: { $0.id == settings.deviceID }) {
            let name = settings.displayName
            let initials = String(name.prefix(1)).uppercased()
            annotations.append(MemberAnnotation(
                id: settings.deviceID,
                name: name + " (you)",
                initials: initials,
                coordinate: myLoc,
                lastMessagePreview: nil,
                isOnline: true
            ))
        }

        return annotations
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hollerBackground.ignoresSafeArea()

                mapContent

                // Show enable button if not sharing with channel
                if let channel = activeChannel, !channel.isLocationSharingActive {
                    VStack {
                        Spacer()
                        Button {
                            var updated = channel
                            updated.locationSharingEnabled = true
                            updated.locationSharingExpiry = Date().addingTimeInterval(4 * 3600)
                            settings.activeChannel = updated
                            locationManager.startSharing()
                        } label: {
                            Label("Share with channel", systemImage: "location.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.hollerTextPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(Color.hollerAccent)
                                )
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Always start location updates for the map (separate from sharing with channel)
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestPermission()
                }
                if locationManager.authorizationStatus == .authorizedWhenInUse ||
                   locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingForMap()
                }
            }
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // Show self with initials (same style as other members)
                if let myLoc = locationManager.currentLocation {
                    Annotation(settings.displayName + " (you)", coordinate: myLoc) {
                        Text(String(settings.displayName.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.hollerTextPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.hollerAccent))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                ForEach(memberAnnotations) { annotation in
                    Annotation(annotation.name, coordinate: annotation.coordinate) {
                        memberPin(annotation)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .bottom)

            // Selected member detail overlay
            if let selectedID = selectedMemberID,
               let annotation = memberAnnotations.first(where: { $0.id == selectedID }) {
                VStack {
                    Spacer()
                    memberDetailCard(annotation)
                        .padding()
                }
            }

            // Member count badge
            VStack {
                HStack {
                    Spacer()
                    Text("\(memberAnnotations.count) sharing")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding()
                Spacer()
            }
        }
    }

    // MARK: - Member Pin

    private func memberPin(_ annotation: MemberAnnotation) -> some View {
        Button {
            withAnimation {
                selectedMemberID = selectedMemberID == annotation.id ? nil : annotation.id
            }
        } label: {
            VStack(spacing: 2) {
                Text(annotation.initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.hollerTextPrimary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(annotation.isOnline ? Color.hollerAccent : Color.hollerOffline)
                    )
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: selectedMemberID == annotation.id ? 2 : 0)
                    )

                // Pin tail
                Triangle()
                    .fill(annotation.isOnline ? Color.hollerAccent : Color.hollerOffline)
                    .frame(width: 10, height: 6)
            }
        }
    }

    // MARK: - Member Detail Card

    private func memberDetailCard(_ annotation: MemberAnnotation) -> some View {
        HStack(spacing: 12) {
            Text(annotation.initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.hollerTextPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.hollerAccent))

            VStack(alignment: .leading, spacing: 4) {
                Text(annotation.name)
                    .font(.headline)
                    .foregroundStyle(Color.hollerTextPrimary)

                if let preview = annotation.lastMessagePreview {
                    Text("Last: \"\(preview)\"")
                        .font(.caption)
                        .foregroundStyle(Color.hollerTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                selectedMemberID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.hollerTextSecondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Location Disabled

    private var locationDisabledView: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.hollerTextSecondary)

            Text("Location Sharing Off")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.hollerTextPrimary)

            Text("Enable location sharing in your active channel to see members on the map.")
                .font(.subheadline)
                .foregroundStyle(Color.hollerTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let channel = activeChannel {
                Button {
                    var updated = channel
                    updated.locationSharingEnabled = true
                    updated.locationSharingExpiry = Date().addingTimeInterval(4 * 3600)
                    settings.activeChannel = updated
                    locationManager.startSharing()
                } label: {
                    Label("Enable for \(channel.name)", systemImage: "location.fill")
                        .font(.headline)
                        .foregroundStyle(Color.hollerTextPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.hollerAccent)
                        )
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct MemberAnnotation: Identifiable {
    let id: String
    let name: String
    let initials: String
    let coordinate: CLLocationCoordinate2D
    let lastMessagePreview: String?
    let isOnline: Bool
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
