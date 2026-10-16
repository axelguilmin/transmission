// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

import SwiftUI
import WidgetKit

struct TorrentsEntry: TimelineEntry {
    let date: Date
}

struct TorrentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TorrentsEntry {
        TorrentsEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (TorrentsEntry) -> Void) {
        completion(TorrentsEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TorrentsEntry>) -> Void) {
        completion(Timeline(entries: [TorrentsEntry(date: .now)], policy: .never))
    }
}

struct TorrentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "org.m0k.transmission.torrents", provider: TorrentsProvider()) { _ in
            Text("Transmission")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Transmission")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TransmissionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TorrentsWidget()
    }
}
