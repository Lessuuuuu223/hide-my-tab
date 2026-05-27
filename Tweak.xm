#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 验证码列表（你设置的） ==========
static NSArray * const ACTIVATE_CODES = @[
    @"xiannvbenxian",
    @"fengzheng",
    @"wushaoshe",
];

// ========== 提前声明函数 ==========
static void showDisclaimerAlert(UIWindow *window);
static void showActivateAlert(UIWindow *window);
static void showToast(NSString *message, UIColor *color);
static BOOL needActivate();
static void saveActivateTime();

// ========== 移除多余Tab ==========
%hook UITabBarController
- (void)viewDidLoad {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray *vcs = self.viewControllers;
        if (!vcs || vcs.count <= 2) return;
        self.selectedIndex = 0;
        NSArray *newVCs = [vcs subarrayWithRange:NSMakeRange(0, 2)];
        [self setViewControllers:newVCs animated:NO];
    });
}
%end

// ========== 启动时加载弹窗 ==========
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        UIWindowScene *windowScene = (UIWindowScene *)scene;
                        for (UIWindow *w in windowScene.windows) {
                            if (w.isKeyWindow) {
                                keyWindow = w;
                                break;
                            }
                        }
                        if (keyWindow) break;
                    }
                }
            }
            if (!keyWindow) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                keyWindow = [UIApplication sharedApplication].keyWindow;
                #pragma clang diagnostic pop
            }
            if (!keyWindow || !keyWindow.rootViewController) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *retryWindow = nil;
                    if (@available(iOS 13.0, *)) {
                        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                            if ([scene isKindOfClass:[UIWindowScene class]]) {
                                UIWindowScene *windowScene = (UIWindowScene *)scene;
                                for (UIWindow *w in windowScene.windows) {
                                    if (w.isKeyWindow) {
                                        retryWindow = w;
                                        break;
                                    }
                                }
                                if (retryWindow) break;
                            }
                        }
                    }
                    if (!retryWindow) {
                        #pragma clang diagnostic push
                        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        retryWindow = [UIApplication sharedApplication].keyWindow;
                        #pragma clang diagnostic pop
                    }
                    if (retryWindow && retryWindow.rootViewController) {
                        showDisclaimerAlert(retryWindow);
                    }
                });
                return;
            }
            showDisclaimerAlert(keyWindow);
        });
    });
}
%end

// ========== Toast提示 ==========
static void showToast(NSString *message, UIColor *color) {
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
    if (!window) return;
    for (UIView *v in window.subviews) {
        if (v.tag == 9999) [v removeFromSuperview];
    }
    UILabel *label = [[UILabel alloc] init];
    label.tag = 9999;
    label.text = message;
    label.textColor = [UIColor whiteColor];
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

// ========== 激活状态检查 ==========
static BOOL needActivate() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id obj = [defaults objectForKey:@"hmt_last_activate_time"];
    if (!obj || ![obj isKindOfClass:[NSNumber class]]) return YES;
    NSTimeInterval lastTime = [(NSNumber *)obj doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return (now - lastTime) > 2592000;
}
static void saveActivateTime() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"hmt_last_activate_time"];
    [defaults synchronize];
}

// ========== 原生免责声明弹窗 ==========
static void showDisclaimerAlert(UIWindow *window) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"声明" message:@"该软件仅用于内部使用，请勿用于非法用途，违者后果自负。\n\n软件有问题联系【乌梢蛇】处理，其他问题一概不知。" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"我已知晓" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (needActivate()) {
            showActivateAlert(window);
        }
    }];
    [alert addAction:cancel];
    [alert addAction:agree];
    dispatch_async(dispatch_get_main_queue(), ^{
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ========== 原生激活码输入弹窗 ==========
static void showActivateAlert(UIWindow *window) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活验证" message:@"请输入激活码，激活后可使用30天" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入激活码";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.secureTextEntry = YES;
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"确认激活" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text;
        BOOL valid = NO;
        for (NSString *code in ACTIVATE_CODES) {
            if ([input isEqualToString:code]) {
                valid = YES;
                break;
            }
        }
        if (valid) {
            saveActivateTime();
            showToast(@"✅ 激活成功", [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0]);
        } else {
            showToast(@"❌ 验证码错误，请重试", [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                showActivateAlert(window);
            });
        }
    }];
    [alert addAction:cancel];
    [alert addAction:confirm];
    dispatch_async(dispatch_get_main_queue(), ^{
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}
