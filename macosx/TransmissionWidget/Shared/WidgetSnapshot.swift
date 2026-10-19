// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

import Foundation

/// What the app shares with its widget: the torrents as the main window shows them.
/// Compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable {
    /// Bumped on any incompatible change; the widget ignores snapshots of another version.
    static let currentVersion = 2
    static let fileName = "widget-snapshot.json"
    static let widgetKind = "org.m0k.transmission.torrents"

    enum FilterStatus: String, Codable {
        case downloading
        case seeding
        case paused
        case error
    }

    struct Torrent: Codable {
        var id: Int
        var name: String
        /// Bytes of the files selected for download.
        var sizeSelected: Int64
        var progress: Double
        var filterStatus: FilterStatus
        /// Currently transferring data.
        var isActive: Bool
        var hasErrorOrWarning: Bool
        var statusString: String
        var progressString: String
    }

    var version: Int
    var written: Date
    /// While running, the app writes and reloads the widget again by this time.
    var nextUpdate: Date
    /// False once the app has quit.
    var running: Bool
    var downloadRate: String
    var uploadRate: String
    /// In the main window's sort order.
    var torrents: [Torrent]

    /// The snapshot in the default config directory. The widget can't use NSHomeDirectory(),
    /// which points into its sandbox container.
    static var defaultFileURL: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Application Support/Transmission")
            .appendingPathComponent(fileName)
    }
}
