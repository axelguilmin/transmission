// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

import AppIntents
import SwiftUI
import WidgetKit

/// Data this late past the snapshot's nextUpdate, or written by an app that has quit, gets an "as of" time.
private let staleDelay: TimeInterval = 60
/// No update this late past the snapshot's nextUpdate means the app crashed.
private let notRunningDelay: TimeInterval = 2 * 60

/// The main window's filter bar choices the widget offers, with the same meanings.
enum TorrentFilter: String, AppEnum {
    case downloading
    case active
    case all

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Filter", comment: "Widget configuration -> which torrents to show"))
    static let caseDisplayRepresentations: [TorrentFilter: DisplayRepresentation] = [
        .downloading: DisplayRepresentation(title: LocalizedStringResource("Downloading", comment: "Widget -> filter name")),
        .active: DisplayRepresentation(title: LocalizedStringResource("Active", comment: "Widget -> filter name")),
        .all: DisplayRepresentation(title: LocalizedStringResource("All", comment: "Widget -> filter name")),
    ]

    func includes(_ torrent: WidgetSnapshot.Torrent) -> Bool {
        switch self {
        case .downloading:
            return torrent.filterStatus == .downloading
        case .active:
            return (torrent.filterStatus == .downloading || torrent.filterStatus == .seeding) && torrent.isActive
        case .all:
            return true
        }
    }

    var name: Text {
        switch self {
        case .downloading:
            return Text("Downloading", comment: "Widget -> filter name")
        case .active:
            return Text("Active", comment: "Widget -> filter name")
        case .all:
            return Text("All", comment: "Widget -> filter name")
        }
    }

    var emptyText: Text {
        switch self {
        case .downloading:
            return Text("No downloading torrents", comment: "Widget -> no torrent matches the filter")
        case .active:
            return Text("No active torrents", comment: "Widget -> no torrent matches the filter")
        case .all:
            return Text("No torrents", comment: "Widget -> no torrent matches the filter")
        }
    }
}

struct TorrentsConfigurationIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Torrents", comment: "Widget configuration -> title")

    @Parameter(title: LocalizedStringResource("Filter", comment: "Widget configuration -> which torrents to show"),
               default: .downloading)
    var filter: TorrentFilter
}

struct TorrentsEntry: TimelineEntry {
    enum Content {
        case missing
        case snapshot(WidgetSnapshot, isStale: Bool, isRunning: Bool)
    }

    let date: Date
    let filter: TorrentFilter
    let content: Content
}

struct TorrentsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TorrentsEntry {
        TorrentsEntry(date: .now, filter: .downloading, content: .snapshot(.placeholder, isStale: false, isRunning: true))
    }

    func snapshot(for configuration: TorrentsConfigurationIntent, in context: Context) async -> TorrentsEntry {
        if context.isPreview {
            return TorrentsEntry(date: .now,
                                 filter: configuration.filter,
                                 content: .snapshot(.placeholder, isStale: false, isRunning: true))
        }
        return entries(filter: configuration.filter, now: .now)[0]
    }

    func timeline(for configuration: TorrentsConfigurationIntent, in context: Context) async -> Timeline<TorrentsEntry> {
        let now = Date.now
        return Timeline(entries: entries(filter: configuration.filter, now: now),
                        policy: .after(now.addingTimeInterval(15 * 60)))
    }

    /// The entry for now, plus the ones that age it if the app stops writing.
    private func entries(filter: TorrentFilter, now: Date) -> [TorrentsEntry] {
        guard let snapshot = loadSnapshot() else {
            return [TorrentsEntry(date: now, filter: filter, content: .missing)]
        }
        guard snapshot.running else {
            return [TorrentsEntry(date: now, filter: filter, content: .snapshot(snapshot, isStale: true, isRunning: false))]
        }

        let staleDate = snapshot.nextUpdate.addingTimeInterval(staleDelay)
        let notRunningDate = snapshot.nextUpdate.addingTimeInterval(notRunningDelay)
        return ([now] + [staleDate, notRunningDate].filter { $0 > now })
            .map { date in
                TorrentsEntry(date: date,
                              filter: filter,
                              content: .snapshot(snapshot, isStale: date >= staleDate, isRunning: date < notRunningDate))
            }
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let url = WidgetSnapshot.defaultFileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }
}

struct TorrentsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TorrentsEntry

    var body: some View {
        switch entry.content {
        case .missing:
            Text("Can't find Transmission data", comment: "Widget -> no snapshot to read")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case let .snapshot(snapshot, isStale, isRunning):
            VStack(alignment: .leading, spacing: 6) {
                if !isRunning {
                    Text("Transmission isn't running", comment: "Widget -> app has quit or stopped responding")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Group {
                    if family == .systemSmall {
                        SmallView(snapshot: snapshot, filter: entry.filter)
                    } else {
                        ListView(snapshot: snapshot, filter: entry.filter, maxRows: family == .systemLarge ? 6 : 3)
                    }
                }
                .opacity(isRunning ? 1 : 0.4)
                if isStale {
                    Text("As of \(snapshot.written, style: .time)", comment: "Widget -> time the shown data was written")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Count, overall progress and speed of the torrents the filter shows.
private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let filter: TorrentFilter

    var body: some View {
        let torrents = snapshot.torrents.filter(filter.includes)
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(torrents.count)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            filter.name
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if torrents.isEmpty {
                Text(verbatim: "↑ \(snapshot.uploadRate)")
                    .font(.caption)
            } else {
                ProgressBar(value: overallProgress(of: torrents))
                Text(verbatim: "↓ \(snapshot.downloadRate)")
                    .font(.caption)
            }
        }
    }

    private func overallProgress(of torrents: [WidgetSnapshot.Torrent]) -> Double {
        let total = torrents.reduce(0.0) { $0 + Double($1.sizeSelected) }
        guard total > 0 else {
            return torrents.reduce(0.0) { $0 + $1.progress } / Double(torrents.count)
        }
        return torrents.reduce(0.0) { $0 + Double($1.sizeSelected) * $1.progress } / total
    }
}

/// Main-window-like rows of the torrents the filter shows.
private struct ListView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    let filter: TorrentFilter
    let maxRows: Int

    var body: some View {
        let torrents = snapshot.torrents.filter(filter.includes)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                filter.name
                    .font(.headline)
                Spacer()
                Text(verbatim: "↓ \(snapshot.downloadRate)  ↑ \(snapshot.uploadRate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if torrents.isEmpty {
                Spacer(minLength: 0)
                filter.emptyText
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(torrents.prefix(maxRows), id: \.id) { torrent in
                    TorrentRow(torrent: torrent, showsStatus: family == .systemLarge)
                }
                if torrents.count > maxRows {
                    Text("+\(torrents.count - maxRows) more", comment: "Widget -> torrents that don't fit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Like a main-window row: name, progress with time remaining, and optionally the status line.
private struct TorrentRow: View {
    let torrent: WidgetSnapshot.Torrent
    let showsStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(torrent.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(torrent.progressString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressBar(value: torrent.progress)
            if showsStatus || torrent.hasErrorOrWarning {
                Text(torrent.statusString)
                    .font(.caption2)
                    .foregroundStyle(torrent.hasErrorOrWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
    }
}

/// ProgressView draws its track and fill in the same color in the desktop's vibrant rendering,
/// so this draws a dimmer track explicitly.
private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.2))
                Capsule()
                    .fill(.tint)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
                    .widgetAccentable()
            }
        }
        .frame(height: 4)
    }
}

private extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        version: currentVersion,
        written: .now,
        nextUpdate: .now,
        running: true,
        downloadRate: "2.4 MB/s",
        uploadRate: "310 KB/s",
        torrents: [
            Torrent(id: 1,
                    name: "debian-13.1.0-amd64-netinst.iso",
                    sizeSelected: 700_000_000,
                    progress: 0.62,
                    filterStatus: .downloading,
                    isActive: true,
                    hasErrorOrWarning: false,
                    statusString: "Downloading from 12 of 40 peers",
                    progressString: "434 MB of 700 MB (62%)"),
            Torrent(id: 2,
                    name: "ubuntu-26.04-desktop-amd64.iso",
                    sizeSelected: 6_000_000_000,
                    progress: 0.18,
                    filterStatus: .downloading,
                    isActive: true,
                    hasErrorOrWarning: false,
                    statusString: "Downloading from 8 of 31 peers",
                    progressString: "1.08 GB of 6 GB (18%)"),
        ])
}

struct TorrentsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshot.widgetKind,
                               intent: TorrentsConfigurationIntent.self,
                               provider: TorrentsProvider()) { entry in
            TorrentsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text(verbatim: "Transmission"))
        .description(Text("Keep an eye on the torrents you're downloading.", comment: "Widget gallery -> widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TransmissionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TorrentsWidget()
    }
}
