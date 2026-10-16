// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

import SwiftUI
import WidgetKit

/// Data older than this gets an "as of" time.
private let staleAge: TimeInterval = 2 * 60
/// The app rewrites the snapshot every minute while it runs; data older than this means it crashed.
private let notRunningAge: TimeInterval = 3 * 60

struct TorrentsEntry: TimelineEntry {
    enum Content {
        case missing
        case snapshot(WidgetSnapshot, isStale: Bool, isRunning: Bool)
    }

    let date: Date
    let content: Content
}

struct TorrentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TorrentsEntry {
        TorrentsEntry(date: .now, content: .snapshot(.placeholder, isStale: false, isRunning: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (TorrentsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(now: .now)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TorrentsEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: entries(now: now), policy: .after(now.addingTimeInterval(15 * 60))))
    }

    /// The entry for now, plus the ones that age it if the app stops writing.
    private func entries(now: Date) -> [TorrentsEntry] {
        guard let snapshot = loadSnapshot() else {
            return [TorrentsEntry(date: now, content: .missing)]
        }
        guard snapshot.running else {
            return [TorrentsEntry(date: now, content: .snapshot(snapshot, isStale: true, isRunning: false))]
        }

        let staleDate = snapshot.written.addingTimeInterval(staleAge)
        let notRunningDate = snapshot.written.addingTimeInterval(notRunningAge)
        return ([now] + [staleDate, notRunningDate].filter { $0 > now })
            .map { date in
                TorrentsEntry(date: date,
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
            Text("Can't find Transmission data")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case let .snapshot(snapshot, isStale, isRunning):
            VStack(alignment: .leading, spacing: 6) {
                if !isRunning {
                    Text("Transmission isn't running")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Group {
                    if family == .systemSmall {
                        SmallView(snapshot: snapshot)
                    } else {
                        ListView(snapshot: snapshot, maxRows: family == .systemLarge ? 6 : 3)
                    }
                }
                .opacity(isRunning ? 1 : 0.4)
                if isStale && isRunning {
                    Text("As of \(snapshot.written, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Count, overall progress and speed of the downloading torrents.
private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let torrents = snapshot.downloading
        VStack(alignment: .leading, spacing: 4) {
            Text("\(torrents.count)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Text("Downloading")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if torrents.isEmpty {
                Text("↑ \(snapshot.uploadRate)")
                    .font(.caption)
            } else {
                ProgressView(value: overallProgress(of: torrents))
                Text("↓ \(snapshot.downloadRate)")
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

/// Main-window-like rows of the downloading torrents.
private struct ListView: View {
    let snapshot: WidgetSnapshot
    let maxRows: Int

    var body: some View {
        let torrents = snapshot.downloading
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading")
                    .font(.headline)
                Spacer()
                Text("↓ \(snapshot.downloadRate)  ↑ \(snapshot.uploadRate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if torrents.isEmpty {
                Spacer(minLength: 0)
                Text("No downloading torrents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(torrents.prefix(maxRows), id: \.id) { torrent in
                    TorrentRow(torrent: torrent)
                }
                if torrents.count > maxRows {
                    Text("+\(torrents.count - maxRows) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TorrentRow: View {
    let torrent: WidgetSnapshot.Torrent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(torrent.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: torrent.progress)
            Text(torrent.statusString)
                .font(.caption2)
                .foregroundStyle(torrent.hasErrorOrWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }
}

private extension WidgetSnapshot {
    var downloading: [Torrent] {
        torrents.filter { $0.filterStatus == .downloading }
    }

    static let placeholder = WidgetSnapshot(
        version: currentVersion,
        written: .now,
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
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: TorrentsProvider()) { entry in
            TorrentsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Transmission")
        .description("Keep an eye on the torrents you're downloading.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TransmissionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TorrentsWidget()
    }
}
