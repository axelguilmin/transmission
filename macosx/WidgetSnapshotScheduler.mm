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
/// The snapshot is rewritten at least this often, so the widget can tell a crashed app from an idle one.
static NSTimeInterval const kHeartbeatInterval = 60.0;

@interface WidgetSnapshotScheduler ()

@property(nonatomic, readonly) NSString* fConfigDirectory;
@property(nonatomic) NSString* fWrittenSignature;
@property(nonatomic) NSDate* fLastReload;
@property(nonatomic) NSDate* fLastWrite;
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
        _fLastWrite = NSDate.distantPast;
    }
    return self;
}

- (void)updateWithTorrents:(NSArray<Torrent*>*)torrents downloadRate:(CGFloat)downloadRate uploadRate:(CGFloat)uploadRate
{
    self.fTorrents = torrents;
    self.fDownloadRate = downloadRate;
    self.fUploadRate = uploadRate;

    NSString* signature = [self signatureOfTorrents:torrents];
    NSTimeInterval const sinceReload = -self.fLastReload.timeIntervalSinceNow;

    if (![signature isEqualToString:self.fWrittenSignature])
    {
        if (sinceReload >= kMeaningChangeReloadInterval)
        {
            [self writeRunning:YES reload:YES signature:signature];
        }
        return;
    }

    BOOL anyTransfer = NO;
    for (Torrent* torrent in torrents)
    {
        if (torrent.filterStatus == TorrentFilterStatusDownloading || torrent.transmitting)
        {
            anyTransfer = YES;
            break;
        }
    }

    if (anyTransfer && sinceReload >= kTransferReloadInterval)
    {
        [self writeRunning:YES reload:YES signature:signature];
    }
    else if (-self.fLastWrite.timeIntervalSinceNow >= kHeartbeatInterval)
    {
        [self writeRunning:YES reload:NO signature:signature];
    }
}

- (void)writeNotRunning
{
    [self writeRunning:NO reload:YES signature:nil];
}

#pragma mark - Private

/// What the widget's content depends on beyond progress and speeds: which torrents, in which order, in which state.
- (NSString*)signatureOfTorrents:(NSArray<Torrent*>*)torrents
{
    NSMutableString* signature = [NSMutableString string];
    for (Torrent* torrent in torrents)
    {
        [signature appendFormat:@"%d:%ld:%d,", torrent.id, (long)torrent.filterStatus, torrent.anyErrorOrWarning];
    }
    return signature;
}

- (void)writeRunning:(BOOL)running reload:(BOOL)reload signature:(NSString*)signature
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
                            toDirectory:self.fConfigDirectory
                                 reload:reload];

    self.fWrittenSignature = signature;
    self.fLastWrite = [NSDate date];
    if (reload)
    {
        self.fLastReload = self.fLastWrite;
    }
}

@end
