#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

// ========== 工具函数 ==========

static NSString* getDeviceCode() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *code = [defaults stringForKey:@"hmta_device_code"];
    if (!code) {
        NSString *chars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        NSMutableString *result = [NSMutableString string];
        for (int i = 0; i < 16; i++) {
            u_int32_t r = arc4random_uniform((u_int32_t)[chars length]);
            [result appendFormat:@"%C", [chars characterAtIndex:r]];
        }
        code = [result copy];
        [defaults setObject:code forKey:@"hmta_device_code"];
        [defaults synchronize];
    }
    return code;
}

static NSString* formatDeviceCode(NSString *code) {
    if (code.length != 16) return code;
    return [NSString stringWithFormat:@"%@-%@-%@-%@",
            [code substringWithRange:NSMakeRange(0,4)],
            [code substringWithRange:NSMakeRange(4,4)],
            [code substringWithRange:NSMakeRange(8,4)],
            [code substringWithRange:NSMakeRange(12,4)]];
}

static long getTimeWindow() {
    return (long)([[NSDate date] timeIntervalSince1970] / 30);
}

static NSString* generateCode() {
    NSString *seed = [NSString stringWithFormat:@"%@|%ld", getDeviceCode(), getTimeWindow()];
    const char *cStr = [seed UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cStr, (CC_LONG)strlen(cStr), digest);
    unsigned int hash = 0;
    for (int i = 0; i < 4; i++) {
        hash = (hash << 8) + digest[i];
    }
    unsigned int code = hash % 1000000;
    return [NSString stringWithFormat:@"%06u", code];
}

static UIWindow *GetKeyWindow() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                if (window) break;
            }
        }
    }
    if (!window) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        window = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    return window;
}

static BOOL needVerify() {
    NSDate *lastVerify = [[NSUserDefaults standardUserDefaults] objectForKey:@"hmta_last_verify"];
    if (!lastVerify) return YES;
    NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:lastVerify];
    return diff > 2592000;
}

// ========== Toast（不依赖 UIAlertController）==========

static void showToast(NSString *message) {
    UIWindow *window = GetKeyWindow();
    if (!window) return;
    
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:16];
    label.layer.cornerRadius = 8;
    label.layer.masksToBounds = YES;
    
    CGSize size = [message boundingRectWithSize:CGSizeMake(250, 999)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: label.font}
                                        context:nil].size;
    label.frame = CGRectMake(0, 0, size.width + 30, size.height + 20);
    label.center = CGPointMake(window.center.x, window.center.y - 80);
    
    [window addSubview:label];
    
    [UIView animateWithDuration:0.3 delay:1.5 options:UIViewAnimationOptionCurveEaseIn animations:^{
        label.alpha = 0;
    } completion:^(BOOL finished) {
        [label removeFromSuperview];
    }];
}

// ========== 免责声明（纯文本，无 attributedMessage）==========

static void showDisclaimerAlert(UIWindow *window, void (^onAgree)(void)) {
    // ⚠️ iOS 16 安全做法：不用 attributedMessage，纯文本 + 强调符号
    NSString *msg = @"⚠️ 该软件仅用于内部研究使用\n\n❌ 禁止向外流通\n❌ 禁止用于任何非法用途\n\n📞 有任何问题联系【乌梢蛇】处理";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    // ❌ 去掉 setValue:forKey:@"attributedMessage"
    // ❌ 去掉 modalPresentationStyle = UIModalPresentationOverFullScreen
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (onAgree) onAgree();
    }];
    
    [alert addAction:cancel];
    [alert addAction:agree];
    
    // ✅ 标准 present，不设置 modalPresentationStyle
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 验证码弹窗（标准样式）==========

static void showVerifyAlert(UIWindow *window) {
    NSString *deviceCode = formatDeviceCode(getDeviceCode());
    NSString *currentCode = generateCode();
    NSLog(@"[HideMyTabAuth] Device: %@ | Code: %@", deviceCode, currentCode);
    
    NSString *msg = [NSString stringWithFormat:@"设备码: %@\n\n请输入6位动态验证码\n（验证码每30秒更新）", deviceCode];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"安全验证"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入6位验证码";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.secureTextEntry = NO;
        textField.textAlignment = NSTextAlignmentCenter;
        textField.font = [UIFont systemFontOfSize:20];
    }];
    
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"📋 复制设备码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = deviceCode;
        showToast(@"设备码已复制到剪贴板");
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"验证并进入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text;
        if ([input isEqualToString:currentCode]) {
            NSDate *now = [NSDate date];
            [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"hmta_last_verify"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSLog(@"[HideMyTabAuth] Verify success");
        } else {
            exit(0);
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    [alert addAction:copyAction];
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 主流程 ==========

static void startAuthFlow(UIWindow *window) {
    if (!needVerify()) return;
    showDisclaimerAlert(window, ^{
        showVerifyAlert(window);
    });
}

// ========== Hook ==========

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // ✅ 延迟 2 秒，等 App 完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = GetKeyWindow();
            if (!keyWindow) keyWindow = self;
            
            // ✅ 双重检查 rootViewController
            if (!keyWindow.rootViewController) {
                NSLog(@"[HideMyTabAuth] rootViewController nil, retrying...");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *retryWindow = GetKeyWindow() ?: self;
                    if (retryWindow.rootViewController) {
                        startAuthFlow(retryWindow);
                    }
                });
                return;
            }
            
            startAuthFlow(keyWindow);
        });
    });
}

%end

%hook UIApplicationDelegate

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    static BOOL firstLaunch = YES;
    if (firstLaunch) {
        firstLaunch = NO;
        return;
    }
    
    if (!needVerify()) return;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (window && window.rootViewController) {
            startAuthFlow(window);
        }
    });
}

%end
