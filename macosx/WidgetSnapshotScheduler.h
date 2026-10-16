// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

#import <Foundation/Foundation.h>

@class Torrent;

/// Decides when to rewrite the widget snapshot and when to ask WidgetKit for a reload,
/// which the system rations.
@interface WidgetSnapshotScheduler : NSObject

- (instancetype)initWithConfigDirectory:(NSString*)configDirectory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Call on every UI update, with torrents in the main window's sort order.
- (void)updateWithTorrents:(NSArray<Torrent*>*)torrents downloadRate:(CGFloat)downloadRate uploadRate:(CGFloat)uploadRate;

/// Marks the snapshot as written by an app that has quit.
- (void)writeNotRunning;

@end
