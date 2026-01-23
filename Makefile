THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222
ARCHS = arm64
PACKAGE_ARCH = iphoneos-arm
THEOS_PACKAGE_ARCH = iphoneos-arm
THEOS_PACKAGE_ARCHS = iphoneos-arm
LOGOS_DEFAULT_GENERATOR = internal
INSTALL_TARGET_PROCESSES = SpringBoard
DEBUG=0
FINALPACKAGE=1

# 定义打包模式常量
ROOTFULL = 0
ROOTLESS = 1
ROOTHIDE = 2

# 默认使用 rootfull (0)，可通过命令行覆盖，如 `make TYPE=1` 选择 rootless
TYPE ?= $(ROOTFULL)

TARGET = iphone:clang:16.5:15.0
ifeq ($(TYPE), $(ROOTLESS))
    THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(TYPE), $(ROOTHIDE))
    THEOS_PACKAGE_SCHEME = roothide
else 
	TARGET = iphone:clang:16.5:12.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProjectXTweak
APPLICATION_NAME = ProjectX
TOOL_NAME = ProjectXDaemon

# Tweak files
ProjectXTweak_FILES = $(wildcard hooks/*.x) $(wildcard common/*.m) $(wildcard hooks/*.m) $(wildcard model/*.m) libs/fishhook.c
ProjectXTweak_CFLAGS = -fobjc-arc -Wno-error=unused-variable -Wno-error=unused-function -I./include -I./common -I./model
ProjectXTweak_FRAMEWORKS = UIKit Foundation AdSupport UserNotifications IOKit Security CoreLocation CoreFoundation Network CoreTelephony SystemConfiguration WebKit SafariServices
ProjectXTweak_PRIVATE_FRAMEWORKS = MobileCoreServices AppSupport SpringBoardServices
ProjectXTweak_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries



# App files
ProjectX_FILES = $(wildcard *.m) $(wildcard common/*.m) $(wildcard model/*.m)
ProjectX_RESOURCE_DIRS = Assets.xcassets
ProjectX_RESOURCE_FILES = Info.plist Icon.png LaunchScreen.storyboard
ProjectX_PRIVATE_FRAMEWORKS = FrontBoardServices SpringBoardServices BackBoardServices StoreKitUI MobileCoreServices
# ProjectX_LDFLAGS = -framework CoreData -framework UIKit -framework Foundation 
ProjectX_FRAMEWORKS = UIKit Foundation MobileCoreServices CoreServices StoreKit IOKit Security CoreLocation
ProjectX_CODESIGN_FLAGS = -Sent.plist
ProjectX_CFLAGS = -fobjc-arc -D SUPPORT_IPAD=1 -D ENABLE_STATE_RESTORATION=1  -I./common -I./model
ProjectX_EXTRA_FRAMEWORKS = AltList
ProjectX_LDFLAGS += -F$(THEOS)/lib -weak_framework CoreLocationUI

# Ensure app is installed to the correct location with proper permissions
ProjectX_INSTALL_PATH = /Applications

ProjectXDaemon_FILES = $(wildcard daemon/*.m) $(wildcard model/*.m) ./common/ProfileManager.m ./common/SettingManager.m ./common/ProjectXLogging.m ./common/PXBundleIdentifier.m
ProjectXDaemon_CFLAGS = -fobjc-arc -I./model -I./common -I./headers
ProjectXDaemon_FRAMEWORKS = Foundation IOKit
ProjectXDaemon_INSTALL_PATH = /usr/local/bin
ProjectXDaemon_CODESIGN_FLAGS = -Sent.plist
ProjectXDaemon_LDFLAGS = -framework IOKit
# ProjectXDaemon_EXTRA_FRAMEWORKS = GCDWebServers
ProjectXDaemon_LDFLAGS += -L./libs
ProjectXDaemon_LDFLAGS += -lGCDWebServers

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

after-package::
	@set -e; \
	if ! command -v dpkg-deb >/dev/null; then \
		echo "dpkg-deb not found; skipping package architecture rewrite."; \
		exit 0; \
	fi; \
	deb=$$(ls -t packages/*.deb 2>/dev/null | head -n 1); \
	if [ -z "$$deb" ]; then \
		echo "No package found to rewrite."; \
		exit 0; \
	fi; \
	case "$$deb" in \
		*iphoneos-arm64*) ;; \
		*) exit 0 ;; \
	esac; \
	tmp=$$(mktemp -d); \
	dpkg-deb -R "$$deb" "$$tmp"; \
	sed -i.bak -E 's/^Architecture:.*/Architecture: iphoneos-arm/' "$$tmp/DEBIAN/control"; \
	newdeb="$${deb/iphoneos-arm64/iphoneos-arm}"; \
	dpkg-deb -b "$$tmp" "$$newdeb" >/dev/null; \
	rm -rf "$$tmp"; \
	if [ "$$deb" != "$$newdeb" ]; then \
		rm -f "$$deb"; \
	fi;



export CFLAGS = -fobjc-arc -Wno-error
