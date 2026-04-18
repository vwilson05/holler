import SwiftUI

/// Main tab-based navigation: Channels | Talk | Map | Settings
struct MainTabView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: ConnectionManager
    @EnvironmentObject var audio: AudioManager

    @State var selectedTab = 1 // Default to Talk tab

    var channelColor: Color {
        Color(hex: settings.activeChannel?.colorHex ?? "#FF6B47")
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChannelListView(switchToTalk: { selectedTab = 1 })
                .tabItem {
                    Image(systemName: "rectangle.stack.fill")
                    Text("Channels")
                }
                .tag(0)

            TalkView()
                .tabItem {
                    Image(systemName: "mic.fill")
                    Text("Talk")
                }
                .tag(1)

            MapTabView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Map")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .tint(channelColor)
        .onAppear {
            configureTabBarAppearance()
            if !connection.isActive {
                connection.start()
            }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.hollerCard)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ConnectionManager.shared)
        .environmentObject(AudioManager.shared)
        .preferredColorScheme(.dark)
}
