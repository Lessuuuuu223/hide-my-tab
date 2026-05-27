#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 验证码列表（你设置的） ==========
static NSArray * const ACTIVATE_CODES = @[
    @"xiannvbenxian",
    @"fengzheng",
    @"wushaoshe",
];

// ========== 远程停用配置（✅ 已修正为正确的raw链接） ==========
static NSString * const kRemoteStatusURL = @"https://gitee.com/huang-xuxuxuxu/hide-my-tab-control/raw/master/status.json";
static NSTimeInterval const kCheckInterval = 60; // 每1分钟检测一次

// ========== 提前声明函数 ==========
static void showDisclaimerAlert(UIWindow *window);
static void showActivateAlert(UIWindow *window);
static void showToast(NSString *message, UIColor *color);
static void showRemainingDaysAlert(UIWindow *window, void (^completion)(void));
static BOOL needActivate();
static NSInteger getRemainingDays();
static void saveActivateTime();
static void checkRemoteStatus(void);
static void showDisabledAlert(void);
static void startPeriodicCheck(void);
static UIWindow *getKeyWindow(void);

// ========== 全局标记 ==========
static BOOL gIsRemoteDisabled = NO;

// ========== 移除多余Tab ==========
%hook UITabBarController
- (void)viewDidLoad {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // 只有在未被远程停用的情况下才隐藏Tab
        if (!gIsRemoteDisabled) {
            NSArray *vcs = self.viewControllers;
            if (!vcs || vcs.count <= 2) return;
            self.selectedIndex = 0;
            NSArray *newVCs = [vcs subarrayWithRange:NSMakeRange(0, 2)];
            [self setViewControllers:newVCs animated:NO];
        }
    });
}
%end

// ========== 启动时检查 ==========
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checkRemoteStatus(); // 启动立即自检一次远程值
        startPeriodicCheck();
        
        // 延迟0.5秒显示免责声明，确保远程状态检查完成
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!gIsRemoteDisabled) {
                showDisclaimerAlert(self);
            }
        });
    });
}
%end

// ========== 获取正确Window ==========
static UIWindow *getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow && !window.hidden) {
                        return window;
                    }
                }
            }
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

// ========== 定时循环检测 ==========
static void startPeriodicCheck(void) {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, kCheckInterval * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        if (gIsRemoteDisabled) {
            dispatch_source_cancel(timer);
            return;
        }
        checkRemoteStatus();
    });
    
    dispatch_resume(timer);
}

// ========== ✅ 修复后的远程状态检查（添加缓存绕过+详细日志） ==========
static void checkRemoteStatus(void) {
    // 添加随机参数绕过Gitee CDN缓存
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSString *urlString = [NSString stringWithFormat:@"%@?t=%f", kRemoteStatusURL, timestamp];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url 
                                             cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData 
                                         timeoutInterval:10];
    
    NSLog(@"[HideMyTab] 正在检查远程状态: %@", urlString);
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL enabled = YES;
        
        if (error) {
            NSLog(@"[HideMyTab] 远程检查失败: %@", error.localizedDescription);
            // 网络错误时默认启用，避免误杀
            enabled = YES;
        } else if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[HideMyTab] 远程返回内容: %@", responseString);
            
            NSError *jsonError = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[HideMyTab] JSON解析失败: %@", jsonError.localizedDescription);
                NSLog(@"[HideMyTab] 请确认URL是raw链接而不是blob链接！");
                enabled = YES;
            } else if ([json isKindOfClass:[NSDictionary class]]) {
                NSNumber *enabledNum = json[@"enabled"];
                if (enabledNum) {
                    enabled = [enabledNum boolValue];
                    NSLog(@"[HideMyTab] 远程状态: %@", enabled ? @"启用" : @"停用");
                }
            } else if ([json isKindOfClass:[NSNumber class]]) {
                enabled = [json boolValue];
                NSLog(@"[HideMyTab] 远程状态: %@", enabled ? @"启用" : @"停用");
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!enabled) {
                gIsRemoteDisabled = YES;
                showDisabledAlert();
            }
        });
    }];
    [task resume];
}

// ========== 停用弹窗 ==========
static void showDisabledAlert(void) {
    static BOOL shown = NO;
    if (shown) return;
    shown = YES;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ 已停用" message:@"该软件已停用，请联系乌梢蛇。" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *exitBtn = [UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        exit(0);
    }];
    [alert addAction:exitBtn];
    
    UIWindow *window = getKeyWindow();
    if (window && window.rootViewController) {
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    } else {
        exit(0);
    }
}

// ========== Toast提示 ==========
static void showToast(NSString *message, UIColor *color) {
    UIWindow *window = getKeyWindow();
    if (!window) return;
    
    for (UIView *v in window.subviews) {
        if (v.tag == 9999) [v removeFromSuperview];
    }
    
    UILabel *label = [[UILabel alloc] init];
    label.tag = 9999;
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = color ?: [UIColor colorWithWhite:0 alpha:0.8];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    
    CGSize size = [message boundingRectWithSize:CGSizeMake(280, 999) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: label.font} context:nil].size;
    label.frame = CGRectMake(0, 0, size.width + 32, size.height + 16);
    label.center = CGPointMake(window.center.x, window.center.y - 60);
    [window addSubview:label];
    
    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        label.alpha = 0;
    } completion:^(BOOL finished) {
        [label removeFromSuperview];
    }];
}

// ========== 获取剩余激活天数 ==========
static NSInteger getRemainingDays() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id obj = [ud objectForKey:@"hmt_last_activate_time"];
    if (!obj || ![obj isKindOfClass:[NSNumber class]]) return 0;
    
    NSTimeInterval last = [(NSNumber *)obj doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval totalSeconds = 2592000; // 30天总秒数
    NSTimeInterval elapsed = now - last;
    
    if (elapsed >= totalSeconds) {
        return 0;
    } else {
        return (NSInteger)ceil((totalSeconds - elapsed) / 86400); // 向上取整天数
    }
}

// ========== 剩余天数弹窗（2秒自动关闭） ==========
static void showRemainingDaysAlert(UIWindow *window, void (^completion)(void)) {
    NSInteger days = getRemainingDays();
    NSString *message;
    
    if (days == 0) {
        message = @"您的激活已过期，请重新激活";
    } else {
        message = [NSString stringWithFormat:@"剩余激活天数：%ld天", (long)days];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活状态" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [window.rootViewController presentViewController:alert animated:YES completion:^{
        // 2秒后自动关闭弹窗并执行后续操作
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (completion) {
                    completion();
                }
            }];
        });
    }];
}

// ========== 激活逻辑 ==========
static BOOL needActivate() {
    return getRemainingDays() == 0;
}

static void saveActivateTime() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"hmt_last_activate_time"];
    [ud synchronize];
}

// ========== 免责弹窗（加粗+红色按钮） ==========
static void showDisclaimerAlert(UIWindow *window) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"声明" message:@"" preferredStyle:UIAlertControllerStyleAlert];
    
    if (@available(iOS 13.0, *)) {
        NSMutableAttributedString *titleAttr = [[NSMutableAttributedString alloc] initWithString:@"声明" attributes:@{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:20],
            NSForegroundColorAttributeName: UIColor.blackColor
        }];
        [alert setValue:titleAttr forKey:@"attributedTitle"];
    }
    
    NSString *msg = @"该软件仅用于内部使用，切勿传播，勿用于非法用途，违者后果自负。\n\n软件有问题联系【乌梢蛇】处理，其他问题一概不知。";
    NSMutableAttributedString *msgAttr = [[NSMutableAttributedString alloc] initWithString:msg attributes:@{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:17],
        NSForegroundColorAttributeName: UIColor.blackColor
    }];
    [alert setValue:msgAttr forKey:@"attributedMessage"];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        exit(0);
    }];
    
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"我已知晓" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        showRemainingDaysAlert(window, ^{
            if (needActivate()) {
                showActivateAlert(window);
            }
        });
    }];
    
    if (@available(iOS 13.0, *)) {
        [agree setValue:UIColor.redColor forKey:@"titleTextColor"];
    } else {
        alert.view.tintColor = UIColor.redColor;
    }
    
    [alert addAction:cancel];
    [alert addAction:agree];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

// ========== 激活弹窗 ==========
static void showActivateAlert(UIWindow *window) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活验证" message:@"请输入激活码" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"请输入激活码";
        tf.keyboardType = UIKeyboardTypeDefault;
        tf.secureTextEntry = YES;
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        exit(0);
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"确认激活" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *input = alert.textFields.firstObject.text;
        BOOL ok = NO;
        for (NSString *code in ACTIVATE_CODES) {
            if ([input isEqualToString:code]) {
                ok = YES;
                break;
            }
        }
        if (ok) {
            saveActivateTime();
            showToast(@"✅ 激活成功，有效期30天", [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1]);
        } else {
            showToast(@"❌ 验证码错误，请重试", [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                showActivateAlert(window);
            });
        }
    }];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}
