#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

// ========== 动态验证码模块 ==========

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

// 显示验证弹窗
static void showVerifyAlert(UIWindow *window) {
    NSString *currentCode = generateCode();
    NSLog(@"[Verify] Current code: %@", currentCode);
    
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
            // 验证成功，记录当前时间，30天内免验证
            NSDate *now = [NSDate date];
            [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"last_verify_time"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSLog(@"[Verify] Success, valid until: %@", [now dateByAddingTimeInterval:30*24*3600]);
        } else {
            UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"验证失败"
                                                                          message:@"验证码错误，App即将关闭"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                exit(0);
            }];
            [fail addAction:ok];
            [window.rootViewController presentViewController:fail animated:YES completion:nil];
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    alert.modalPresentationStyle = UIModalPresentationOverFullScreen;
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// 检查是否需要验证（30天有效期）
static BOOL needVerify() {
    NSDate *lastVerify = [[NSUserDefaults standardUserDefaults] objectForKey:@"last_verify_time"];
    if (!lastVerify) return YES;
    
    // 30天 = 30 * 24 * 3600 秒 = 2592000 秒
    NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:lastVerify];
    return diff > 2592000;
}

// ========== 移除"我的"Tab代码（原始版本） ==========

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

// ========== 启动验证Hook ==========

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (needVerify()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showVerifyAlert(self);
            });
        }
    });
}

%end

%hook UIApplicationDelegate

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    if (needVerify()) {
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (window) {
            showVerifyAlert(window);
        }
    }
}

%end
