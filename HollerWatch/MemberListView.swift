import SwiftUI

struct MemberListView: View {
    @StateObject private var ws = WatchWebSocketManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Self (always shown)
                HStack(spacing: 8) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                    Text(connectivity.displayName.isEmpty ? "You" : connectivity.displayName)
                        .font(.body)
                    Spacer()
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Other members
                ForEach(ws.members.filter { $0.id != connectivity.deviceId }) { member in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(member.isOnline ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(member.name)
                            .font(.body)
                        Spacer()
                        if member.isOnline {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if ws.members.filter({ $0.id != connectivity.deviceId }).isEmpty {
                    Text("No one else is here yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Channel")
        }
    }
}

#Preview {
    MemberListView()
}
