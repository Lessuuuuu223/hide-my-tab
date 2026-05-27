#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

// ========== 工具函数 ==========

// 获取设备UDID
static NSString* getDeviceID() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *udid = [defaults stringForKey:@"device_udid"];
    if (!udid) {
        udid = [[UIDevice currentDevice].identifierForVendor UUIDString];
        [defaults setObject:udid forKey:@"device_udid"];
        [defaults synchronize];
    }
    return udid;
}

// 生成当前时间窗口（每30秒一个窗口）
static long getTimeWindow() {
    return (long)([[NSDate date] timeIntervalSince1970] / 30);
}

// 生成动态验证码（6位数字）
static NSString* generateCode() {
    NSString *seed = [NSString stringWithFormat:@"%@|%ld", getDeviceID(), getTimeWindow()];
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

// 兼容 iOS 13+ 获取 keyWindow（修复编译错误）
static UIWindow *GetKeyWindow() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                // 遍历 windows 数组找 isKeyWindow（兼容 iOS 13/14）
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
    // iOS 13 以下 fallback，用 pragma 抑制弃用警告
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

// ========== 免责声明弹窗 ==========

static void showDisclaimerAlert(UIWindow *window, void (^onAgree)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                  message:@"该软件仅用于内部研究使用，禁止向外流通，禁止用于任何非法用途，有任何问题联系乌梢蛇处理。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    // 取消按钮（点击退出App）
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        gIsVerifying = NO;
        exit(0);
    }];
    
    // 同意按钮（红色，点击进入验证码环节）
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (onAgree) onAgree();
    }];
    
    [alert addAction:cancel];
    [alert addAction:agree];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 验证码弹窗 ==========

static void showVerifyAlert(UIWindow *window) {
    NSString *currentCode = generateCode();
    NSLog(@"[HideMyTab] Current verify code: %@", currentCode);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"安全验证"
                                                                  message:@"请输入6位动态验证码\n（验证码每30秒更新）"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入6位验证码";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.secureTextEntry = NO;
        textField.textAlignment = NSTextAlignmentCenter;
        textField.font = [UIFont systemFontOfSize:20];
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"验证并进入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text;
        if ([input isEqualToString:currentCode]) {
            // 验证成功，记录30天有效期
            NSDate *now = [NSDate date];
            [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"last_verify_time"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSLog(@"[HideMyTab] Verify success, valid until: %@", [now dateByAddingTimeInterval:30*24*3600]);
            gIsVerifying = NO; // 放行
        } else {
            // 验证失败，直接退出
            gIsVerifying = NO;
            exit(0);
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        gIsVerifying = NO;
        exit(0);
    }];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 统一安全验证入口 ==========

static void startSecurityFlow(UIWindow *window) {
    if (gIsVerifying) return;      // 已在验证中，防止重复弹窗
    if (!needVerify()) return;       // 30天内已验证，直接放行
    
    gIsVerifying = YES;
    
    // 先免责声明 → 同意后 → 验证码
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

// ========== 启动Hook ==========

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startSecurityFlow(self);
        });
    });
}

%end

%hook UIApplicationDelegate

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    // 首次启动已在 makeKeyAndVisible 中处理，这里跳过首次
    static BOOL hasEnteredForeground = NO;
    if (!hasEnteredForeground) {
        hasEnteredForeground = YES;
        return;
    }
    
    // 从后台返回时，如果30天过期，重新走完整流程
    UIWindow *window = GetKeyWindow();
    if (window) {
        startSecurityFlow(window);
    }
}

%end
