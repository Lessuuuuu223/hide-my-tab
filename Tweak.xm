#import <UIKit/UIKit.h>

// ========== 远程停用开关配置 ==========
static NSArray * const REMOTE_URLS = @[
    @"https://gitee.com/huang-xuxuxuxu/hide-my-tab-control/raw/master/status.json"
];

// ========== 全局状态变量 ==========
static BOOL gRemoteChecking = NO;
static NSTimer *gCheckTimer = nil;

// ========== 前向声明 ==========
static void checkRemoteStatus(UIWindow *window, void (^onContinue)(void));

// ========== 日期单双数激活码 ==========
static NSArray* getTodayActivateCodes() {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger day = [calendar component:NSCalendarUnitDay fromDate:[NSDate date]];
    
    if (day % 2 == 0) {
        return @[
            @"fengzheng66",
            @"xiannvbenxian66",
            @"wushaoshe66"
        ];
    }
    return @[
        @"fengzheng99",
        @"xiannvbenxian99",
        @"wushaoshe99"
    ];
}

// ========== 检查激活是否过期（30天）==========
static BOOL needActivate() {
    NSDate *lastActivate = [[NSUserDefaults standardUserDefaults] objectForKey:@"hmta_last_activate"];
    if (!lastActivate) return YES;
    NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:lastActivate];
    return diff > 2592000;
}

// ========== 获取 keyWindow ==========
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

// ========== Toast 提示 ==========
static void showToast(NSString *message, UIColor *color) {
    UIWindow *window = GetKeyWindow();
    if (!window) return;
    
    for (UIView *v in window.subviews) {
        if ([v isKindOfClass:[UILabel class]] && v.tag == 9999) {
            [v removeFromSuperview];
        }
    }
    
    UILabel *label = [[UILabel alloc] init];
    label.tag = 9999;
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = color ?: [UIColor colorWithWhite:0 alpha:0.8];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:18];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    
    CGSize size = [message boundingRectWithSize:CGSizeMake(280, 999)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: label.font}
                                        context:nil].size;
    label.frame = CGRectMake(0, 0, size.width + 40, size.height + 24);
    label.center = CGPointMake(window.center.x, window.center.y - 60);
    
    [window addSubview:label];
    
    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        label.alpha = 0;
    } completion:^(BOOL finished) {
        [label removeFromSuperview];
    }];
}

// ========== 定时器目标类 ==========
@interface HideMyTabAuthTimerTarget : NSObject
@end

@implementation HideMyTabAuthTimerTarget
- (void)timerFired:(NSTimer *)timer {
    UIWindow *window = GetKeyWindow();
    if (window && window.rootViewController) {
        checkRemoteStatus(window, nil);
    }
}
@end

static HideMyTabAuthTimerTarget *gTimerTarget = nil;

// ========== 应用生命周期监听（替代 hook UIApplicationDelegate）==========
@interface HideMyTabAuthObserver : NSObject
@end

@implementation HideMyTabAuthObserver
- (void)appDidBecomeActive:(NSNotification *)note {
    static BOOL firstLaunch = YES;
    if (firstLaunch) {
        firstLaunch = NO;
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (window && window.rootViewController) {
            checkRemoteStatus(window, ^{
                startAuthFlow(window);
                startPeriodicCheck(window);
            });
        }
    });
}
@end

static HideMyTabAuthObserver *gAuthObserver = nil;

// ========== 远程停用相关函数 ==========
static void forceDisableApp(UIWindow *window) {
    [gCheckTimer invalidate];
    gCheckTimer = nil;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"软件已停用"
                                                                  message:@"该软件已停止服务，如有疑问请联系管理员。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        exit(0);
    }];
    [alert addAction:ok];
    
    UIViewController *vc = window.rootViewController;
    if (!vc) {
        exit(0);
    }
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

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
                                         timeoutInterval:5.0];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                id enabled = json[@"enabled"];
                
                if ([enabled isEqual:@NO] || [enabled isEqual:@0] || [enabled isEqualToString:@"false"]) {
                    gRemoteChecking = NO;
                    forceDisableApp(window);
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

static void startPeriodicCheck(UIWindow *window) {
    [gCheckTimer invalidate];
    gCheckTimer = nil;
    
    if (!gTimerTarget) {
        gTimerTarget = [[HideMyTabAuthTimerTarget alloc] init];
    }
    
    gCheckTimer = [NSTimer scheduledTimerWithTimeInterval:300.0
                                                   target:gTimerTarget
                                                 selector:@selector(timerFired:)
                                                 userInfo:nil
                                                  repeats:YES];
}

// ========== 免责声明弹窗 ==========
static void showDisclaimerAlert(UIWindow *window, void (^onAgree)(void)) {
    NSString *msg = @"⚠️ 该软件仅用于内部研究使用\n\n❌ 禁止向外流通\n❌ 禁止用于任何非法用途\n\n📞 有任何问题联系【乌梢蛇】处理";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (onAgree) onAgree();
    }];
    
    [alert addAction:cancel];
    [alert addAction:agree];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 激活码验证弹窗 ==========
static void showActivateAlert(UIWindow *window) {
    NSArray *todayCodes = getTodayActivateCodes();
    NSLog(@"[HideMyTabAuth] Today codes: %@", todayCodes);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活验证"
                                                                  message:@"请输入今日激活码"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入激活码";
        textField.secureTextEntry = YES;
        textField.textAlignment = NSTextAlignmentCenter;
        textField.font = [UIFont systemFontOfSize:18];
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"激活" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text;
        
        BOOL valid = NO;
        for (NSString *code in todayCodes) {
            if ([input isEqualToString:code]) {
                valid = YES;
                break;
            }
        }
        
        if (valid) {
            NSDate *now = [NSDate date];
            [[NSUserDefaults standardUserDefaults] setObject:now forKey:@"hmta_last_activate"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            showToast(@"✅ 激活成功", [UIColor colorWithRed:0 green:0.7 blue:0 alpha:1.0]);
            NSLog(@"[HideMyTabAuth] Activate success");
        } else {
            showToast(@"❌ 激活码错误，请重试", [UIColor colorWithRed:0.8 green:0 blue:0 alpha:1.0]);
            NSLog(@"[HideMyTabAuth] Activate failed: %@", input);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showActivateAlert(window);
            });
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 主流程 ==========
static void startAuthFlow(UIWindow *window) {
    showDisclaimerAlert(window, ^{
        if (needActivate()) {
            showActivateAlert(window);
        }
    });
}

// ========== Hook UIWindow ==========
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 注册应用生命周期监听（安全替代 hook UIApplicationDelegate）
        if (!gAuthObserver) {
            gAuthObserver = [[HideMyTabAuthObserver alloc] init];
            [[NSNotificationCenter defaultCenter] addObserver:gAuthObserver
                                                     selector:@selector(appDidBecomeActive:)
                                                         name:UIApplicationDidBecomeActiveNotification
                                                       object:nil];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = GetKeyWindow();
            if (!keyWindow) keyWindow = self;
            
            if (!keyWindow.rootViewController) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *retryWindow = GetKeyWindow() ?: self;
                    if (retryWindow.rootViewController) {
                        checkRemoteStatus(retryWindow, ^{
                            startAuthFlow(retryWindow);
                            startPeriodicCheck(retryWindow);
                        });
                    }
                });
                return;
            }
            
            checkRemoteStatus(keyWindow, ^{
                startAuthFlow(keyWindow);
                startPeriodicCheck(keyWindow);
            });
        });
    });
}

%end
