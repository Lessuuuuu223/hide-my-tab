#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

// ========== 远程停用开关配置 ==========
static NSArray * const REMOTE_URLS = @[
    @"https://gitee.com/huang-xuxuxuxu/hide-my-tab-control/raw/master/status.json"
];

// ========== 工具函数 ==========

// 生成独立设备码（16位，终身不变）
static NSString* getDeviceCode() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *code = [defaults stringForKey:@"device_code"];
    if (!code) {
        NSString *chars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        NSMutableString *result = [NSMutableString string];
        for (int i = 0; i < 16; i++) {
            u_int32_t r = arc4random_uniform((u_int32_t)[chars length]);
            [result appendFormat:@"%C", [chars characterAtIndex:r]];
        }
        code = [result copy];
        [defaults setObject:code forKey:@"device_code"];
        [defaults synchronize];
    }
    return code;
}

// 设备码格式化显示 XXXX-XXXX-XXXX-XXXX
static NSString* formatDeviceCode(NSString *code) {
    if (code.length != 16) return code;
    return [NSString stringWithFormat:@"%@-%@-%@-%@",
            [code substringWithRange:NSMakeRange(0,4)],
            [code substringWithRange:NSMakeRange(4,4)],
            [code substringWithRange:NSMakeRange(8,4)],
            [code substringWithRange:NSMakeRange(12,4)]];
}

// 生成当前时间窗口（每30秒一个窗口）
static long getTimeWindow() {
    return (long)([[NSDate date] timeIntervalSince1970] / 30);
}

// 生成动态验证码（6位数字）—— 基于设备码
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

// 兼容 iOS 13+ 获取 keyWindow
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

// 检查是否需要验证（30天有效期）
static BOOL needVerify() {
    NSDate *lastVerify = [[NSUserDefaults standardUserDefaults] objectForKey:@"last_verify_time"];
    if (!lastVerify) return YES;
    NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:lastVerify];
    return diff > 2592000;
}

// ========== 防重复标志 ==========
static BOOL gIsVerifying = NO;
static BOOL gRemoteChecking = NO;
static BOOL gHasShownOnce = NO;  // 防止重复弹窗

// ========== 远程停用检查（支持多URL轮询） ==========

static void checkRemoteStatusWithURLs(NSArray *urls, NSUInteger index, UIWindow *window, void (^onContinue)(void)) {
    if (index >= urls.count) {
        gRemoteChecking = NO;
        if (onContinue) onContinue();
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        checkRemoteStatusWithURLs(urls, index + 1, window, onContinue);
        return;
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:3.0];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                id enabled = json[@"enabled"];
                
                if ([enabled isEqual:@NO] || [enabled isEqual:@0] || [enabled isEqualToString:@"false"]) {
                    gRemoteChecking = NO;
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"软件已停用"
                                                                                  message:@"该软件已停止服务，如有疑问请联系管理员。"
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        exit(0);
                    }];
                    [alert addAction:ok];
                    [window.rootViewController presentViewController:alert animated:YES completion:nil];
                    return;
                }
                
                gRemoteChecking = NO;
                if (onContinue) onContinue();
                return;
            }
            
            checkRemoteStatusWithURLs(urls, index + 1, window, onContinue);
        });
    }];
    [task resume];
}

static void checkRemoteStatus(UIWindow *window, void (^onContinue)(void)) {
    if (gRemoteChecking) return;
    gRemoteChecking = YES;
    checkRemoteStatusWithURLs(REMOTE_URLS, 0, window, onContinue);
}

// ========== 免责声明弹窗（字体加大，乌梢蛇标红加粗） ==========

static void showDisclaimerAlert(UIWindow *window, void (^onAgree)(void)) {
    NSString *msg = @"该软件仅用于内部研究使用，禁止向外流通，禁止用于任何非法用途。\n\n有任何问题联系【乌梢蛇】处理";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    NSMutableAttributedString *attrMsg = [[NSMutableAttributedString alloc] initWithString:msg];
    [attrMsg addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15] range:NSMakeRange(0, msg.length)];
    NSRange range = [msg rangeOfString:@"【乌梢蛇】"];
    if (range.location != NSNotFound) {
        [attrMsg addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:range];
        [attrMsg addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:18] range:range];
    }
    @try {
        [alert setValue:attrMsg forKey:@"attributedMessage"];
    } @catch (NSException *e) {}
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        gIsVerifying = NO;
        exit(0);
    }];
    
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (onAgree) onAgree();
    }];
    
    [alert addAction:cancel];
    [alert addAction:agree];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 验证码弹窗（显示设备码 + 一键复制） ==========

static void showVerifyAlert(UIWindow *window) {
    NSString *deviceCode = formatDeviceCode(getDeviceCode());
    NSString *currentCode = generateCode();
    NSLog(@"[HideMyTab] Device: %@ | Code: %@", deviceCode, currentCode);
    
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
    
    // 复制设备码按钮（绿色）
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"📋 复制设备码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = deviceCode;
        // 复制后重新弹出提示
        UIAlertController *copied = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                      message:@"设备码已复制到剪贴板"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [copied addAction:ok];
        [window.rootViewController presentViewController:copied animated:YES completion:nil];
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"验证并进入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text;
        if ([input isEqualToString:currentCode]) {
            NSDate *now = [NSDate date];
            [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"last_verify_time"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSLog(@"[HideMyTab] Verify success");
            gIsVerifying = NO;
            gHasShownOnce = YES;
        } else {
            gIsVerifying = NO;
            exit(0);
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        gIsVerifying = NO;
        exit(0);
    }];
    
    [alert addAction:copyAction];
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 统一安全验证入口 ==========

static void startSecurityFlow(UIWindow *window) {
    if (gIsVerifying) return;
    if (gHasShownOnce && !needVerify()) return;  // 已验证过且未过期，跳过
    
    gIsVerifying = YES;
    
    showDisclaimerAlert(window, ^{
        showVerifyAlert(window);
    });
}

// ========== 移除"我的"Tab ==========

%hook UITabBarController

- (void)viewDidLoad {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray *vcs = self.viewControllers;
        if (!vcs || vcs.count <= 2) return;
        
        NSArray *newVCs = [vcs subarrayWithRange:NSMakeRange(0, 2)];
        self.viewControllers = newVCs;
        
        UITabBar *tabBar = self.tabBar;
        NSArray *items = tabBar.items;
        if (items.count > 2) {
            NSArray *newItems = [items subarrayWithRange:NSMakeRange(0, 2)];
            [tabBar setItems:newItems animated:NO];
        }
    });
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (index >= 2) index = 0;
    %orig(index);
}

%end

// ========== 启动Hook（修复闪退） ==========

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟1.5秒，等App完全初始化完成再弹窗
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = GetKeyWindow();
            if (!keyWindow) keyWindow = self;
            
            // 确保rootViewController已设置
            if (!keyWindow.rootViewController) {
                NSLog(@"[HideMyTab] rootViewController not ready, retrying...");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *retryWindow = GetKeyWindow() ?: self;
                    checkRemoteStatus(retryWindow, ^{
                        startSecurityFlow(retryWindow);
                    });
                });
                return;
            }
            
            checkRemoteStatus(keyWindow, ^{
                startSecurityFlow(keyWindow);
            });
        });
    });
}

%end

%hook UIApplicationDelegate

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    // 首次启动已在 makeKeyAndVisible 中处理，这里直接跳过
    static BOOL hasEnteredForeground = NO;
    if (!hasEnteredForeground) {
        hasEnteredForeground = YES;
        return;
    }
    
    // 后台返回时，如果已验证过且未过期，不再重复弹窗
    if (gHasShownOnce && !needVerify()) return;
    
    // 延迟检查，避免与UI初始化冲突
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (window && window.rootViewController) {
            checkRemoteStatus(window, ^{
                startSecurityFlow(window);
            });
        }
    });
}

%end
