ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HideMyTab

HideMyTab_FILES = Tweak.xm
HideMyTab_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
