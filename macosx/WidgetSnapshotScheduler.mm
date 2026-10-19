// This file Copyright © Transmission authors and contributors.
// It may be used under the MIT (SPDX: MIT) license.
// License text can be found in the licenses/ folder.

#import "WidgetSnapshotScheduler.h"
#import "NSStringAdditions.h"
#import "Torrent.h"
#import "WidgetSnapshotWriter.h"

/// A change in what the widget shows is pushed this soon, bursts coalescing into one reload.
static NSTimeInterval const kMeaningChangeReloadInterval = 5.0;
/// Progress and speeds are refreshed this often while anything is downloading or transferring.
static NSTimeInterval const kTransferReloadInterval = 60.0;
/// Otherwise the widget is still reloaded this often, so it can tell a crashed app from an idle one.
static NSTimeInterval const kIdleReloadInterval = 10 * 60.0;

@interface WidgetSnapshotScheduler ()

@property(nonatomic, readonly) NSString* fConfigDirectory;
@property(nonatomic) NSString* fWrittenSignature;
@property(nonatomic) NSDate* fLastReload;
/// When the written snapshot promises the next one.
@property(nonatomic) NSDate* fNextUpdate;
@property(nonatomic, copy) NSArray<Torrent*>* fTorrents;
@property(nonatomic) CGFloat fDownloadRate;
@property(nonatomic) CGFloat fUploadRate;

@end

@implementation WidgetSnapshotScheduler

- (instancetype)initWithConfigDirectory:(NSString*)configDirectory
{
    if ((self = [super init]))
    {
        _fConfigDirectory = [configDirectory copy];
        _fLastReload = NSDate.distantPast;
        _fNextUpdate = NSDate.distantPast;
    }
    return self;
}

- (void)updateWithTorrents:(NSArray<Torrent*>*)torrents downloadRate:(CGFloat)downloadRate uploadRate:(CGFloat)uploadRate
{
    self.fTorrents = torrents;
    self.fDownloadRate = downloadRate;
    self.fUploadRate = uploadRate;

    BOOL anyTransfer = NO;
    for (Torrent* torrent in torrents)
    {
        if (torrent.filterStatus == TorrentFilterStatusDownloading || torrent.transmitting)
        {
            anyTransfer = YES;
            break;
        }
    }
    NSTimeInterval const reloadInterval = anyTransfer ? kTransferReloadInterval : kIdleReloadInterval;

    NSString* signature = [self signatureOfTorrents:torrents];
    NSTimeInterval const sinceReload = -self.fLastReload.timeIntervalSinceNow;

    BOOL due;
    if (![signature isEqualToString:self.fWrittenSignature])
    {
        due = sinceReload >= kMeaningChangeReloadInterval;
    }
    else
    {
        due = sinceReload >= reloadInterval || self.fNextUpdate.timeIntervalSinceNow <= 0;
    }

    if (due)
    {
        [self writeRunning:YES signature:signature nextUpdate:[NSDate dateWithTimeIntervalSinceNow:reloadInterval]];
    }
}

- (void)writeNotRunning
{
    [self writeRunning:NO signature:nil nextUpdate:NSDate.distantFuture];
}

#pragma mark - Private

/// What the widget's content depends on beyond progress and speeds: which torrents, in which order, in which state,
/// and which are transmitting (the Active filter).
- (NSString*)signatureOfTorrents:(NSArray<Torrent*>*)torrents
{
    NSMutableString* signature = [NSMutableString string];
    for (Torrent* torrent in torrents)
    {
        [signature appendFormat:@"%d:%ld:%d:%d,", torrent.id, (long)torrent.filterStatus, torrent.transmitting,
                                torrent.anyErrorOrWarning];
    }
    return signature;
}

- (void)writeRunning:(BOOL)running signature:(NSString*)signature nextUpdate:(NSDate*)nextUpdate
{
    NSMutableArray<WidgetSnapshotTorrent*>* torrents = [NSMutableArray arrayWithCapacity:self.fTorrents.count];
    for (Torrent* torrent in self.fTorrents)
    {
        [torrents addObject:[[WidgetSnapshotTorrent alloc] initWithID:torrent.id name:torrent.name
                                                         sizeSelected:(int64_t)torrent.totalSizeSelected
                                                             progress:torrent.progress
                                                         filterStatus:torrent.filterStatus
                                                               active:torrent.transmitting
                                                       errorOrWarning:torrent.anyErrorOrWarning
                                                         statusString:torrent.statusString
                                                       progressString:torrent.progressString]];
    }

    [WidgetSnapshotWriter writeTorrents:torrents downloadRate:[NSString stringForSpeed:self.fDownloadRate]
                             uploadRate:[NSString stringForSpeed:self.fUploadRate]
                                running:running
                             nextUpdate:nextUpdate
                            toDirectory:self.fConfigDirectory];

    self.fWrittenSignature = signature;
    self.fLastReload = [NSDate date];
    self.fNextUpdate = nextUpdate;
}

@end
