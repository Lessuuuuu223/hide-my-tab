# 支持的CPU架构：覆盖所有iOS14+设备
# arm64: iPhone 6s ~ iPhone X
# arm64e: iPhone XS及以上所有新设备
ARCHS = arm64 arm64e

# 编译配置（最重要的一行）
# 格式：TARGET = iphone:clang:SDK版本:最低支持系统版本
# 18.5: 使用Xcode16.4自带的最新iOS18.5 SDK编译（兼容性最好）
# 14.0: 编译出来的dylib最低支持iOS14.0系统
TARGET = iphone:clang:18.5:14.0

# 要注入的目标应用Bundle ID
INSTALL_TARGET_PROCESSES = LocationSimulation

# ✅ 非越狱环境核心配置：弱依赖越狱库
# 告诉编译器：CydiaSubstrate不是必须的，找不到也不要崩溃
LDFLAGS += -weak_framework CydiaSubstrate
LDFLAGS += -weak-lsubstrate

# 生成deb包格式
THEOS_PACKAGE_FORMAT = deb
THEOS_PACKAGE_ARCH = iphoneos-arm64

# 开启编译优化，减小最终dylib体积
FINALPACKAGE_CFLAGS += -Os
FINALPACKAGE_LDFLAGS += -dead_strip

# 引入Theos基础编译规则
include $(THEOS)/makefiles/common.mk

# Tweak名称（生成的dylib文件名）
TWEAK_NAME = HideMyTab

# 源文件列表
HideMyTab_FILES = Tweak.xm

# 依赖的系统框架
HideMyTab_FRAMEWORKS = UIKit Foundation

# 编译标志：关闭ARC（你的代码是MRC风格）
HideMyTab_CFLAGS = -fno-objc-arc

# 引入Theos Tweak编译规则
include $(THEOS_MAKE_PATH)/tweak.mk
