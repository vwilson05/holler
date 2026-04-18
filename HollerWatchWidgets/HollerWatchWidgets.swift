import SwiftUI
import WidgetKit

@main
struct HollerWatchWidgets: WidgetBundle {
    var body: some Widget {
        HollerComplication()
    }
}

struct HollerComplication: Widget {
    let kind = "HollerComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HollerComplicationProvider()) { entry in
            complicationView(for: entry)
        }
        .configurationDisplayName("Holler")
        .description("Quick access to your walkie-talkie channel.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }

    @ViewBuilder
    func complicationView(for entry: HollerComplicationEntry) -> some View {
        // WidgetKit picks the right family automatically
        HollerCircularComplication(entry: entry)
    }
}
