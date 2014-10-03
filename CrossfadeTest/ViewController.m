//
//  ViewController.m
//  CrossfadeTest
//
//  Created by Mathew Polzin on 8/25/14.
//  Copyright (c) 2014 Mathew Polzin. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMedia/CoreMedia.h>

#define FADE_SECONDS 8.0
#define FADE_FREQ 0.1
#define FADE_INC FADE_FREQ/FADE_SECONDS

@implementation ViewController
{
	NSMutableArray* players;				// AVPlayer array
	
	NSMutableArray* playerLayers;			// AVPlayerLayer array
	
	NSMutableArray* synchronizedLayers;		// AVSynchronizedLayer array
	
	NSArray* views;							// UIView array
	
	NSTimer* fadeTimer;						// timer that facilitates fading between videos
	id timeObserver;
	
	NSArray* videoURLs;						// NSURL array
	NSMutableArray* videos;					// AVPlayerItem array
	
	NSInteger currentPlayer;
	NSInteger currentItem;
	
	UIButton* skipButton;
	UIView* videoView;
}

- (void) initialize {
	
	currentPlayer = 0;
	currentItem = 0;
	
	skipButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	skipButton.frame = CGRectMake(4, 4, 80, 44);
	[skipButton setTitle:@"skip" forState:UIControlStateNormal];
	[skipButton addTarget:self action:@selector(skip) forControlEvents:UIControlEventAllEvents];
	
	// insert any number of video URLs below. These can be hosted online or part of the local app bundle.
	videoURLs = @[[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"a_fake_movie" ofType:@"mp4"]],
				  [NSURL URLWithString:@"http://url.com/a_fake_movie.mp4"]];
	
	[self fillVideosArray];
	
	players = [[NSMutableArray alloc] initWithObjects:
			   [[AVPlayer alloc] initWithPlayerItem:videos[0]],
			   [[AVPlayer alloc] initWithPlayerItem:videos[1]],
			   nil
			   ];
	
	playerLayers = [[NSMutableArray alloc] initWithObjects:
					[AVPlayerLayer playerLayerWithPlayer:players[0]],
					[AVPlayerLayer playerLayerWithPlayer:players[1]],
					nil
					];
	
	((AVPlayerLayer*)playerLayers[0]).frame = self.view.bounds;
	((AVPlayerLayer*)playerLayers[1]).frame = self.view.bounds;
	
	synchronizedLayers = [[NSMutableArray alloc] initWithObjects:
						  [AVSynchronizedLayer synchronizedLayerWithPlayerItem:videos[0]],
						  [AVSynchronizedLayer synchronizedLayerWithPlayerItem:videos[1]],
						  nil
						  ];
	
	((AVSynchronizedLayer*)synchronizedLayers[0]).frame = self.view.frame;
	((AVSynchronizedLayer*)synchronizedLayers[1]).frame = self.view.frame;
	
	[synchronizedLayers[0] addSublayer:playerLayers[0]];
	[synchronizedLayers[1] addSublayer:playerLayers[1]];
	
	self.view.backgroundColor = [UIColor blackColor];
	
	videoView = [[UIView alloc] initWithFrame:self.view.frame];
	videoView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	videoView.backgroundColor = [UIColor clearColor];
	[self.view addSubview:videoView];
	views = @[[[UIView alloc] initWithFrame:self.view.frame], [[UIView alloc] initWithFrame:self.view.frame]];
	
	((UIView*)views[0]).autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	((UIView*)views[0]).backgroundColor = [UIColor clearColor];
	((UIView*)views[1]).autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	((UIView*)views[1]).backgroundColor = [UIColor clearColor];
	
	[((UIView*)views[0]).layer addSublayer:synchronizedLayers[0]];
	
	[((UIView*)views[1]).layer addSublayer:synchronizedLayers[1]];
	
	((AVPlayerLayer*)playerLayers[1]).opacity = 0.0;
	((AVPlayer*)players[1]).volume = 0.0;
	
	// must add view 1 as subview after the previous two sublayers are set up
	// or else the second view will not be above the first view in the hierarchy.
	[videoView addSubview:views[0]];
	[videoView addSubview:views[1]];

	//put skip botton on top
	[self.view addSubview:skipButton];
	
	[players[0] addObserver:self forKeyPath:@"status" options:0 context:(__bridge void*)@"play"];
	[players[1] addObserver:self forKeyPath:@"status" options:0 context:(__bridge void*)@"preload"];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:videos[0]];
}

- (void)loadNextItem {
	[[self currentPlayer] removeObserver:self forKeyPath:@"rate"];
	
	[views[currentPlayer%players.count] removeFromSuperview];
	[synchronizedLayers[currentPlayer%players.count] removeFromSuperlayer];
	if (timeObserver) {
		[[self currentPlayer] removeTimeObserver:timeObserver];
		timeObserver = nil;
	}
	
	// replace player item that was just used because each can only be used with one player.
	videos[currentItem%videos.count] = [[AVPlayerItem alloc] initWithURL:videoURLs[currentItem%videos.count]];
	
	currentPlayer++;
	NSInteger nextPlayerIdx = (currentPlayer+1)%players.count;
	currentItem++;
	NSInteger nextItemIdx = (currentItem+1)%videos.count;
	
	players[nextPlayerIdx] = [[AVPlayer alloc] initWithPlayerItem:videos[nextItemIdx]];
	playerLayers[nextPlayerIdx] = [AVPlayerLayer playerLayerWithPlayer:players[nextPlayerIdx]];
	
	((AVPlayerLayer*)playerLayers[nextPlayerIdx]).frame = self.view.bounds;
	
	synchronizedLayers[nextPlayerIdx] = [AVSynchronizedLayer synchronizedLayerWithPlayerItem:videos[nextItemIdx]];
	
	[synchronizedLayers[nextPlayerIdx] addSublayer:playerLayers[nextPlayerIdx]];
	
	((UIView*)views[nextPlayerIdx]).autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	
	[((UIView*)views[nextPlayerIdx]).layer addSublayer:synchronizedLayers[nextPlayerIdx]];
	
	((AVPlayerLayer*)playerLayers[nextPlayerIdx]).opacity = 0.0;
	((AVPlayer*)players[nextPlayerIdx]).volume = 0.0;
	
	[videoView addSubview:views[nextPlayerIdx]];
	
	[players[nextPlayerIdx] addObserver:self forKeyPath:@"status" options:0 context:(__bridge void*)@"preload"];
	
	// prepare a fade from the current player to the next one.
	[self prepareFadeForPlayer:[self currentPlayer] nextPlayer:[self nextPlayer] nextLayer:[self nextPlayerLayer]];
	
	[skipButton setEnabled:YES];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	
	[self initialize];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	if ([@"status" isEqualToString:keyPath]) {
		NSString* instruction = (__bridge NSString*)context;
		AVPlayer* player = (AVPlayer*)object;
		[player removeObserver:self forKeyPath:@"status"];
		if (player.status == AVPlayerStatusReadyToPlay) {
			[player prerollAtRate:1.0 completionHandler:^(BOOL finished) {
				if ([instruction isEqualToString:@"play"]) {
					[self startPlayer:player];
					
					if (!timeObserver) {
						// set up the time observer the first time through
						[self prepareFadeForPlayer:[self currentPlayer] nextPlayer:[self nextPlayer] nextLayer:[self nextPlayerLayer]];
					}
				}
			}];
		}
	} else if ([@"rate" isEqualToString:keyPath] ) {
		AVPlayer* player = (AVPlayer*)object;
		if (player.rate == 0 && CMTimeGetSeconds(player.currentItem.duration) != CMTimeGetSeconds(player.currentItem.currentTime))
		{
			[player play];
		}
	}
}

- (void)playerEnd:(NSNotification*)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:[self currentItem]];
	
	[self loadNextItem];
}

- (void)playNextVideo {
	AVPlayer* nextPlayer = [self nextPlayer];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:[self nextItem]];
	
	if (nextPlayer.status == AVPlayerStatusReadyToPlay) {
		[self startPlayer:nextPlayer];
	} else {
		[nextPlayer removeObserver:self forKeyPath:@"status"];
		[nextPlayer addObserver:self forKeyPath:@"status" options:0 context:(__bridge void*)@"play"];
	}
}

- (void)fillVideosArray {
	NSLog(@"filling videos array.");
	videos = [[NSMutableArray alloc] initWithCapacity:3];
	
	for (NSURL* url in videoURLs) {
		[videos addObject:[[AVPlayerItem alloc] initWithURL:url]];
	}
}

- (AVPlayer*)currentPlayer {
	return players[currentPlayer%players.count];
}

- (AVPlayer*)nextPlayer {
	return players[(currentPlayer+1)%players.count];
}

- (AVPlayerLayer*)currentPlayerLayer {
	return playerLayers[currentPlayer%playerLayers.count];
}

- (AVPlayerLayer*)nextPlayerLayer {
	return playerLayers[(currentPlayer+1)%playerLayers.count];
}

- (AVPlayerItem*)currentItem {
	return videos[currentItem%videos.count];
}

- (AVPlayerItem*)nextItem {
	return videos[(currentItem+1)%videos.count];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

- (void)startPlayer:(AVPlayer*)player {
	[player play];
	[player addObserver:self forKeyPath:@"rate" options:0 context:NULL];
}

- (void)skip {
	[[self currentPlayer] seekToTime:CMTimeMakeWithSeconds(CMTimeGetSeconds([self currentPlayer].currentItem.duration)-15, 1)];
}

- (void)prepareFadeForPlayer:(AVPlayer*)player nextPlayer:(AVPlayer*)nextPlayer nextLayer:(AVPlayerLayer*)nextLayer {
	
	NSBlockOperation* bo = [NSBlockOperation blockOperationWithBlock:^{
		nextPlayer.volume += FADE_INC;
		nextLayer.opacity += FADE_INC;
		
		if (nextPlayer.volume >= 1.0 || nextLayer.opacity >= 1.0) {
			nextPlayer.volume = 1.0;
			nextLayer.opacity = 1.0;
			[fadeTimer invalidate];
		}
		
		player.volume -= FADE_INC;
		
		if (player.volume < 0) {
			player.volume = 0;
		}
	}];
	
	timeObserver = [player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:CMTimeMakeWithSeconds(CMTimeGetSeconds(player.currentItem.duration)-FADE_SECONDS, 1)]] queue:NULL usingBlock:^{
		
		[skipButton setEnabled:NO];
		
		fadeTimer = [NSTimer scheduledTimerWithTimeInterval:FADE_FREQ
													 target:bo
												   selector:@selector(main)
												   userInfo:nil
													repeats:YES];
		
		[self playNextVideo];
	}];
}

@end
