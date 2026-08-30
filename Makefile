export ARCHS = armv7
export TARGET = iphone:clang:9.3:6.0
export TARGET_IPHONEOS_DEPLOYMENT_VERSION = 6.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OldEmby

# All ObjC sources - explicit list for determinism (Theos wildcards are fragile on Linux)
OldEmby_FILES = \
	Sources/main.m \
	Sources/AppDelegate.m \
	Sources/Controllers/OELoginViewController.m \
	Sources/Controllers/OELibraryViewController.m \
	Sources/Controllers/OEVideoDetailViewController.m \
	Sources/Controllers/OESettingsViewController.m \
	Sources/Controllers/OEMusicLibraryViewController.m \
	Sources/Controllers/OEMusicPlayerViewController.m \
	Sources/Models/OEEmbyItem.m \
	Sources/Models/OETranscodeSettings.m \
	Sources/Models/OEServerConfig.m \
	Sources/Services/OEEmbyAPIClient.m \
	Sources/Services/OETranscodeBuilder.m \
	Sources/Services/OEImageCache.m \
	Sources/Views/OEItemCell.m

OldEmby_FRAMEWORKS = UIKit Foundation MediaPlayer AVFoundation CoreGraphics QuartzCore CoreMedia AudioToolbox MediaToolbox
OldEmby_PRIVATE_FRAMEWORKS =

# iOS 6 compatibility: no NSURLSession, use NSURLConnection; frame layout, not AutoLayout-dependent
OldEmby_CFLAGS = -fobjc-arc -mios-version-min=6.0 -Wno-deprecated-declarations -Wno-unknown-pragmas -O2 -ISources -I.
OldEmby_LDFLAGS = -Wl,-segalign,4000
OldEmby_CODESIGN_FLAGS = -Sentitlements.plist

# Info.plist additions via Theos
OldEmby_PLIST_FILES = Resources/Info.plist

include $(THEOS_MAKE_PATH)/application.mk

# Post-build: create IPA structure for non-Cydia distribution
after-package::
	@echo "==> Packaging IPA..."
	@rm -rf Payload
	@mkdir -p Payload
	@cp -R $(THEOS_OBJ_DIR)/OldEmby.app Payload/ 2>/dev/null || cp -R .theos/obj/iphoneos/*/OldEmby.app Payload/ 2>/dev/null || true
	@if [ -d Payload/OldEmby.app ]; then \
		echo "Found app bundle, ldid signing..."; \
		ldid -S entitlements.plist Payload/OldEmby.app/OldEmby 2>/dev/null || ldid -Sentitlements.plist Payload/OldEmby.app/OldEmby 2>/dev/null || true; \
		zip -r OldEmby-$(THEOS_PACKAGE_BASE_VERSION)_armv7.ipa Payload > /dev/null; \
		echo "IPA created: OldEmby-$(THEOS_PACKAGE_BASE_VERSION)_armv7.ipa"; \
		ls -lh *.ipa 2>/dev/null || true; \
	fi

after-clean::
	rm -rf Payload *.ipa .theos packages
