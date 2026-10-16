// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

#import <Foundation/Foundation.h>

// Implemented in WidgetSnapshotWriter.swift.

@interface WidgetSnapshotTorrent : NSObject

/// filterStatus is a TorrentFilterStatus value.
- (instancetype)initWithID:(NSInteger)torrentID
                      name:(NSString*)name
              sizeSelected:(int64_t)sizeSelected
                  progress:(double)progress
              filterStatus:(NSInteger)filterStatus
                    active:(BOOL)active
            errorOrWarning:(BOOL)errorOrWarning
              statusString:(NSString*)statusString
            progressString:(NSString*)progressString;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface WidgetSnapshotWriter : NSObject

/// Atomically writes the widget snapshot into directory and, if reload is set, asks WidgetKit to reload the widget.
+ (void)writeTorrents:(NSArray<WidgetSnapshotTorrent*>*)torrents
         downloadRate:(NSString*)downloadRate
           uploadRate:(NSString*)uploadRate
              running:(BOOL)running
          toDirectory:(NSString*)directory
               reload:(BOOL)reload;

@end
