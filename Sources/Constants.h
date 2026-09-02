#ifndef Constants_h
#define Constants_h

// Deployment target guard
// All APIs used must be available on iOS 6.0

// NSUserDefaults keys for transcoding persistence
#define kDefaultsTranscodeResolution   @"OETranscodeResolution"   // NSString: @"480p"/@"720p"/@"1080p"
#define kDefaultsTranscodeBitrate      @"OETranscodeBitrate"      // NSNumber: bps
#define kDefaultsTranscodeDirectPlay   @"OETranscodeDirectPlay"   // BOOL
#define kDefaultsAudioBitrate          @"OEAudioBitrate"          // NSNumber: bps
#define kDefaultsServerHost            @"OEServerHost"            // NSString: http://host:8096
#define kDefaultsServerUserId          @"OEServerUserId"
#define kDefaultsServerToken           @"OEServerToken"
#define kDefaultsServerUsername        @"OEServerUsername"
#define kDefaultsThemeMode             @"OEThemeMode"             // NSInteger: 0=dark 1=light

// Default forced transcode params (PRD)
#define kDefaultResolution             @"720p"
#define kDefaultVideoBitrate           4000000  // 4 Mbps
#define kDefaultAudioBitrate           192000   // 192 kbps AAC
#define kDefaultDirectPlay             NO

// Notification names
#define kNotificationPlaybackStateChanged        @"OEPlaybackStateChanged"
#define kNotificationMusicPlaybackStateChanged   @"OEMusicPlaybackStateChanged"
// Posted once per failure (not on every state publish) so the UI can raise a
// single copyable error sheet. object is the OEMusicPlaybackManager.
#define kNotificationMusicPlaybackFailed         @"OEMusicPlaybackFailed"
#define kNotificationMusicPlaybackProgressChanged @"OEMusicPlaybackProgressChanged"
#define kNotificationMusicMiniPlayerVisibilityChanged @"OEMusicMiniPlayerVisibilityChanged"
#define kNotificationMusicFullPlayerVisibilityChanged @"OEMusicFullPlayerVisibilityChanged"
#define kNotificationThemeDidChange                   @"OEThemeDidChangeNotification"

#endif
