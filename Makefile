export ARCHS = armv7
export TARGET = iphone:clang:9.3:6.0
export TARGET_IPHONEOS_DEPLOYMENT_VERSION = 6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OldEmby

# All ObjC sources - explicit list for determinism (Theos wildcards are fragile on Linux)
OldEmby_FILES = \
	Sources/main.m \
	Sources/AppDelegate.m \
	Sources/Controllers/OELoginViewController.m \
	Sources/Controllers/OELibraryViewController.m \
	Sources/Controllers/OEPosterWallViewController.m \
	Sources/Controllers/OEVideoDetailViewController.m \
	Sources/Controllers/OEEpisodeListViewController.m \
	Sources/Controllers/OESettingsViewController.m \
	Sources/Controllers/OEMusicLibraryViewController.m \
	Sources/Controllers/OEMusicPlayerViewController.m \
	Sources/Controllers/OERootTabBarController.m \
	Sources/Models/OEEmbyItem.m \
	Sources/Models/OELyricsLine.m \
	Sources/Models/OETranscodeSettings.m \
	Sources/Models/OEServerConfig.m \
	Sources/Services/OEEmbyAPIClient.m \
	Sources/Services/OETranscodeBuilder.m \
	Sources/Services/OEImageCache.m \
	Sources/Services/OEMusicPlaybackManager.m \
	Sources/Views/OEItemCell.m \
	Sources/Views/OEPosterGridCell.m \
	Sources/Views/OETheme.m \
	Sources/Views/OEIconFactory.m \
	Sources/Views/OEMiniPlayerView.m

OldEmby_FRAMEWORKS = UIKit Foundation MediaPlayer AVFoundation CoreGraphics QuartzCore CoreMedia AudioToolbox MediaToolbox
OldEmby_PRIVATE_FRAMEWORKS =

# iOS 6 compatibility: no NSURLSession, use NSURLConnection; frame layout, not AutoLayout-dependent
OldEmby_CFLAGS = -fobjc-arc -mios-version-min=6.0 -Wno-deprecated-declarations -Wno-unknown-pragmas -O2 -ISources -I.
OldEmby_LDFLAGS = -Wl,-segalign,4000

# No entitlements: this is a regular GUI app. Theos signs with a plain
# `ldid -S` pseudo-signature, which sideload tools (爱思助手/AltStore/
# Sideloadly) replace wholesale when re-signing. Embedded jailbreak
# entitlements (platform-application, no-container) are not grantable by
# personal certificates and make re-signed installs fail as "damaged".

# Info.plist is picked up automatically: Theos copies the Resources/ dir into
# the .app and moves Resources/Info.plist to the bundle root.
# OldEmby_PLIST_FILES was never a Theos variable - removed.

include $(THEOS_MAKE_PATH)/application.mk

# IPA assembly lives in .github/workflows/build.yml ("Assemble IPA" step),
# which verifies the binary is a real Mach-O before packaging. Building the
# IPA here duplicated that (with a broken ldid -S syntax) and let hollow
# builds pass silently.
after-clean::
	rm -rf Payload *.ipa .theos packages
