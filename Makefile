ARCHS = arm64 arm64e
TARGET = iphone:clang:15.0:15.0
INSTALL_TARGET_PROCESSES = LocationSimulation

# ✅ 非越狱环境核心配置：弱依赖越狱库，找不到也不崩溃
LDFLAGS += -weak_framework CydiaSubstrate
LDFLAGS += -weak-lsubstrate

THEOS_PACKAGE_FORMAT = deb
THEOS_PACKAGE_ARCH = iphoneos-arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HideMyTab

HideMyTab_FILES = Tweak.xm
HideMyTab_FRAMEWORKS = UIKit Foundation
HideMyTab_CFLAGS = -fno-objc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
