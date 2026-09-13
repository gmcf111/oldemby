#import <UIKit/UIKit.h>

// Full-screen direct-play engine built on the vendored kxmovie core
// (Sources/Player).  FFmpeg demuxes and software-decodes the ORIGINAL file
// streamed from Emby (Static=true URL, server does nothing), so containers
// the iOS system player cannot open - MKV, AVI, WMV, DivX, RMVB, VC-1,
// AC3/DTS audio - play without transcoding.
//
// The detail page routes non-native containers here; native mp4/mov keeps
// using MPMoviePlayerViewController for hardware decode.
@interface OEFFmpegPlayerViewController : UIViewController

- (instancetype)initWithContentURLString:(NSString *)urlString;

@property (nonatomic, copy) NSString *movieTitle;
// Emby identifiers used to fetch text subtitles through the server's
// SRT endpoint (same pipeline as the system-player overlay).
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *mediaSourceId;
// Array of OEStreamInfo (Emby subtitle streams) for the 字幕 sheet.
@property (nonatomic, strong) NSArray *subtitleTracks;
// Invoked after the player is dismissed so the presenting page can reset.
@property (nonatomic, copy) void (^dismissHandler)(void);

@end
