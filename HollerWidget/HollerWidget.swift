import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct HollerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HollerEntry {
        HollerEntry(
            date: Date(),
            channelName: "Home",
            memberCount: 3,
            recentMessages: [
                WidgetMessage(sender: "Trang", duration: "2.1s"),
                WidgetMessage(sender: "Khai", duration: "4.5s"),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HollerEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HollerEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> HollerEntry {
        let defaults = UserDefaults(suiteName: "group.com.holler.shared")
        let channelName = defaults?.string(forKey: "widget_channelName") ?? "Home"
        let memberCount = defaults?.integer(forKey: "widget_memberCount") ?? 0

        var messages: [WidgetMessage] = []
        if let data = defaults?.data(forKey: "widget_recentMessages"),
           let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) {
            messages = decoded.compactMap { dict in
                guard let sender = dict["sender"], let duration = dict["duration"] else { return nil }
                return WidgetMessage(sender: sender, duration: duration)
            }
        }

        return HollerEntry(
            date: Date(),
            channelName: channelName,
            memberCount: memberCount,
            recentMessages: messages
        )
    }
}

// MARK: - Entry

struct HollerEntry: TimelineEntry {
    let date: Date
    let channelName: String
    let memberCount: Int
    let recentMessages: [WidgetMessage]
}

struct WidgetMessage: Codable {
    let sender: String
    let duration: String
}

// MARK: - Small Widget View

struct HollerWidgetSmallView: View {
    let entry: HollerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color(hex: "#FF6B47"))
                Text("Holler")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(entry.channelName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                Text("\(entry.memberCount) members")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(hex: "#1A1A1A")
        }
    }
}

// MARK: - Medium Widget View

struct HollerWidgetMediumView: View {
    let entry: HollerEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Channel info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color(hex: "#FF6B47"))
                    Text("Holler")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }

                Text(entry.channelName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(entry.memberCount)")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
            }

            Divider()
                .background(.white.opacity(0.2))

            // Right: Recent messages
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))

                if entry.recentMessages.isEmpty {
                    Text("No messages yet")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    ForEach(entry.recentMessages.prefix(2), id: \.sender) { msg in
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#FF6B47"))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(msg.sender)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(msg.duration)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(hex: "#1A1A1A")
        }
    }
}

// MARK: - Widget Definition

struct HollerWidget: Widget {
    let kind: String = "HollerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HollerTimelineProvider()) { entry in
            HollerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Holler")
        .description("See your active channel and recent messages.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Entry View (switches by family)

struct HollerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: HollerEntry

    var body: some View {
        switch family {
        case .systemMedium:
            HollerWidgetMediumView(entry: entry)
        default:
            HollerWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle (if needed)

@main
struct HollerWidgetBundle: WidgetBundle {
    var body: some Widget {
        HollerWidget()
    }
}

// MARK: - Color Extension for Widget

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
