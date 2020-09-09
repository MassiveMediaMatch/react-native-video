#import <React/RCTConvert.h>
#import "AbloVideo.h"
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>
#import <React/UIView+React.h>
#include <MediaAccessibility/MediaAccessibility.h>
#include <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>

static NSString *const statusKeyPath = @"status";
static NSString *const readyForDisplayKeyPath = @"readyForDisplay";

@interface AbloVideo ()
@property (nonatomic, strong) RCTEventDispatcher* eventDispatcher;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) NSArray *playlist;
@property (nonatomic, assign) NSInteger playlistIndex;
@property (nonatomic, strong) NSDictionary *src;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL repeat;
@property (nonatomic, strong) NSString *resizeMode;
@property (nonatomic, assign) BOOL playerItemObserversSet;
@property (nonatomic, assign) BOOL playerLayerObserverSet;
@end


@implementation AbloVideo

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
	if ((self = [super init])) {
		self.eventDispatcher = eventDispatcher;
		self.playlistIndex = -1;
		self.resizeMode = @"AVLayerVideoGravityResizeAspectFill";
				
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
	}
	
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - App lifecycle handlers

- (void)applicationWillResignActive:(NSNotification *)notification
{
	[self.player pause];
	[self.player setRate:0.0];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
	
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
	
}


#pragma mark - setters & getters

- (void)setSrc:(NSDictionary *)src
{
	if ([[_src objectForKey:@"uri"] isEqualToString:[src objectForKey:@"uri"]]) {
		return;
	}
	_src = src;
	[self removePlayerLayer];
	[self removePlayerItemObservers];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) 0), dispatch_get_main_queue(), ^{
		
		// perform on next run loop, otherwise other passed react-props may not be set
		__weak __typeof(self)weakSelf = self;
		[self playerItemForSource:src withCallback:^(AVPlayerItem *playerItem) {
			
			weakSelf.playerItem = playerItem;
			[weakSelf addPlayerItemObservers];
			
			weakSelf.player = [AVPlayer playerWithPlayerItem:weakSelf.playerItem];
			if (@available(iOS 10.0, *)) {
				weakSelf.player.automaticallyWaitsToMinimizeStalling = NO;
			}
			[weakSelf.player pause];
			
			weakSelf.playerLayer = [AVPlayerLayer playerLayerWithPlayer:weakSelf.player];
			weakSelf.playerLayer.frame = self.bounds;
			weakSelf.playerLayer.needsDisplayOnBoundsChange = YES;
			weakSelf.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
			[weakSelf.playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
			weakSelf.playerLayerObserverSet = YES;
			[weakSelf.layer addSublayer:weakSelf.playerLayer];
			weakSelf.layer.needsDisplayOnBoundsChange = YES;
			
		}];
	});
}

- (void)setPlaylist:(NSArray *)playlist
{
	_playlist = playlist;
	
	if (_playlistIndex >= 0) {
		[self setPlaylistIndex:_playlistIndex];
	}
}

- (void)setPlaylistIndex:(NSInteger)playlistIndex
{
	_playlistIndex = playlistIndex;
	if (playlistIndex < _playlist.count) {
		NSString *uri = _playlist[playlistIndex];
		[self setSrc: @{@"uri": uri, @"isNetwork": @(YES), @"isAsset":@(NO)}];
	} else {
		NSLog(@"playlistIndex out of bounds");
	}
}

- (void)setPaused:(BOOL)paused
{
	if (paused) {
		[self.player pause];
		[self.player setRate:0.0];
	}
	else
	{
		[self.playerItem seekToTime:kCMTimeZero];
		if (@available(iOS 10.0, *)) {
			[self.player playImmediatelyAtRate:1.0];
		} else {
			[self.player play];
		}
		
		[self.player setRate:1.0];
	}
	
	_paused = paused;
}

- (void)setRepeat:(BOOL)repeat {
	_repeat = repeat;
}

- (void)setResizeMode:(NSString*)mode
{
	_playerLayer.videoGravity = mode;
	_resizeMode = mode;
}


#pragma mark - public

- (void)displayIndex:(NSInteger)index {
	[self setPlaylistIndex:index];
}


#pragma mark - helpers

- (void)applyModifiers
{
	[self setResizeMode:self.resizeMode];
	[self setRepeat:self.repeat];
	[self setPaused:self.paused];
}

- (void)addPlayerItemObservers
{
	[self.playerItem addObserver:self forKeyPath:statusKeyPath options:0 context:nil];
	self.playerItemObserversSet = YES;
}

- (void)removePlayerItemObservers
{
	if (self.playerItemObserversSet) {
		[self.playerItem removeObserver:self forKeyPath:statusKeyPath];
		self.playerItemObserversSet = NO;
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if([keyPath isEqualToString:readyForDisplayKeyPath] && [change objectForKey:NSKeyValueChangeNewKey] && self.onReadyForDisplay) {
		self.onReadyForDisplay(@{@"target": self.reactTag});
		return;
	}

	if (object == _playerItem)
	{
		if ([keyPath isEqualToString:statusKeyPath])
		{
			if (_playerItem.status == AVPlayerItemStatusReadyToPlay)
			{
				[self applyModifiers];
			}
			else if ([super respondsToSelector:@selector(observeValueForKeyPath:ofObject:change:context:)]) {
				[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
			}
		}
		else if ([super respondsToSelector:@selector(observeValueForKeyPath:ofObject:change:context:)]) {
			[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		}
	} else if ([super respondsToSelector:@selector(observeValueForKeyPath:ofObject:change:context:)]) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)removePlayerLayer
{
	[self.playerLayer removeFromSuperlayer];
	if (self.playerLayerObserverSet) {
		[self.playerLayer removeObserver:self forKeyPath:readyForDisplayKeyPath];
		self.playerLayerObserverSet = NO;
	}
	self.playerLayer = nil;
}

- (void)playerItemForSource:(NSDictionary *)source withCallback:(void(^)(AVPlayerItem *))handler
{
	bool isNetwork = [RCTConvert BOOL:[source objectForKey:@"isNetwork"]];
	NSString *uri = [source objectForKey:@"uri"];
	NSURL *url = [NSURL URLWithString:uri];
	NSMutableDictionary *assetOptions = [[NSMutableDictionary alloc] init];
	
	if (isNetwork) {
		NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
		[assetOptions setObject:cookies forKey:AVURLAssetHTTPCookiesKey];
		AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOptions];
		
		AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
		if (@available(iOS 10.0, *)) {
			playerItem.preferredForwardBufferDuration = 0.0;
			playerItem.preferredPeakBitRate = 1;
		}
		if (@available(iOS 11.0, *)) {
			playerItem.preferredMaximumResolution = CGSizeMake(640, 320);
		}
		handler(playerItem);
		return;
	}
}

@end
