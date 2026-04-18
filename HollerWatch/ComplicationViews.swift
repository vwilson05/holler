import SwiftUI
import WidgetKit

// MARK: - Complication Provider

struct HollerComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HollerComplicationEntry {
        HollerComplicationEntry(date: Date(), roomCode: "ROOM", memberCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (HollerComplicationEntry) -> Void) {
        let entry = HollerComplicationEntry(
            date: Date(),
            roomCode: UserDefaults.standard.string(forKey: WatchSettingsKey.roomCode) ?? "---",
            memberCount: WatchWebSocketManager.shared.peerCount
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HollerComplicationEntry>) -> Void) {
        let entry = HollerComplicationEntry(
            date: Date(),
            roomCode: UserDefaults.standard.string(forKey: WatchSettingsKey.roomCode) ?? "---",
            memberCount: WatchWebSocketManager.shared.peerCount
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 5)))
        completion(timeline)
    }
}

// MARK: - Entry

struct HollerComplicationEntry: TimelineEntry {
    let date: Date
    let roomCode: String
    let memberCount: Int

    var roomInitial: String {
        String(roomCode.prefix(1)).uppercased()
    }
}

// MARK: - Complication Views

struct HollerCircularComplication: View {
    let entry: HollerComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(entry.roomInitial)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("\(entry.memberCount)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HollerRectangularComplication: View {
    let entry: HollerComplicationEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.body)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.roomCode)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Text("\(entry.memberCount) online")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct HollerInlineComplication: View {
    let entry: HollerComplicationEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text("\(entry.roomCode) - \(entry.memberCount) online")
        }
    }
}

struct HollerCornerComplication: View {
    let entry: HollerComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
        }
    }
}
