// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

import Foundation
import WidgetKit
import os

// Declared to Objective-C in WidgetSnapshotWriter.h: the app target builds without modules,
// so it can't import the generated Swift header.

@objc(WidgetSnapshotTorrent)
final class WidgetSnapshotTorrent: NSObject {
    let torrent: WidgetSnapshot.Torrent

    /// filterStatus takes a TorrentFilterStatus value from Torrent.h.
    @objc(initWithID:name:sizeSelected:progress:filterStatus:active:errorOrWarning:statusString:progressString:)
    init(id: Int,
         name: String,
         sizeSelected: Int64,
         progress: Double,
         filterStatus: Int,
         active: Bool,
         errorOrWarning: Bool,
         statusString: String,
         progressString: String) {
        // Raw values of TorrentFilterStatus in Torrent.h
        let status: WidgetSnapshot.FilterStatus
        switch filterStatus {
        case 0: status = .downloading
        case 1: status = .seeding
        case 3: status = .error
        default: status = .paused
        }
        torrent = WidgetSnapshot.Torrent(id: id,
                                         name: name,
                                         sizeSelected: sizeSelected,
                                         progress: progress,
                                         filterStatus: status,
                                         isActive: active,
                                         hasErrorOrWarning: errorOrWarning,
                                         statusString: statusString,
                                         progressString: progressString)
    }
}

@objc(WidgetSnapshotWriter)
final class WidgetSnapshotWriter: NSObject {
    private static let log = Logger(subsystem: "org.m0k.transmission", category: "widget")

    @objc(writeTorrents:downloadRate:uploadRate:running:toDirectory:reload:)
    static func write(torrents: [WidgetSnapshotTorrent],
                      downloadRate: String,
                      uploadRate: String,
                      running: Bool,
                      toDirectory directory: String,
                      reload: Bool) {
        let snapshot = WidgetSnapshot(version: WidgetSnapshot.currentVersion,
                                      written: Date(),
                                      running: running,
                                      downloadRate: downloadRate,
                                      uploadRate: uploadRate,
                                      torrents: torrents.map(\.torrent))
        let url = URL(fileURLWithPath: directory).appendingPathComponent(WidgetSnapshot.fileName)
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            log.error("Writing the widget snapshot failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if reload {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
            log.debug("Requested a widget reload")
        }
    }
}
