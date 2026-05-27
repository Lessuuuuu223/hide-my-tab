#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 验证码列表（你设置的） ==========
static NSArray * const ACTIVATE_CODES = @[
    @"xiannvbenxian",
    @"fengzheng",
    @"wushaoshe",
];

// ========== 远程停用配置 ==========
static NSString * const kRemoteStatusURL = @"https://gitee.com/huang-xuxuxuxu/hide-my-tab-control/raw/master/status.json";
static NSTimeInterval const kCheckInterval = 180; // 3分钟检测一次（180秒）

// ========== 提前声明函数 ==========
static void showDisclaimerAlert(UIWindow *window);
static void showActivateAlert(UIWindow *window);
static void showToast(NSString *message, UIColor *color);
static BOOL needActivate();
static void saveActivateTime();
static void checkRemoteStatus(void);
static void showDisabledAlert(void);
static void startPeriodicCheck(void);

// ========== 全局标记：是否已经被远程停用 ==========
static BOOL gIsRemoteDisabled = NO;

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

// ========== 启动时：先检查远程状态 ==========
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checkRemoteStatus(); // 启动立即检查
        startPeriodicCheck(); // 启动 3 分钟循环检测
    });
}
%end

// ========== 每 3 分钟自动检查一次 ==========
static void startPeriodicCheck(void) {
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_BACKGROUND, 0);
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

// ========== 远程状态检查（适配你的 {"enabled": true} 格式） ==========
static void checkRemoteStatus(void) {
    NSURL *url = [NSURL URLWithString:kRemoteStatusURL];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL enabled = YES;
        
        if (!error && data) {
            NSError *jsonError;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if ([json isKindOfClass:[NSDictionary class]]) {
                // 适配你的字段：enabled
                NSNumber *enabledValue = json[@"enabled"];
                if (enabledValue && ![enabledValue boolValue]) {
                    enabled = NO;
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!enabled) {
                gIsRemoteDisabled = YES;
                showDisabledAlert(); // 直接触发停用
            }
        });
    }];
    [task resume];
}

// ========== 远程停用弹窗 ==========
static void showDisabledAlert(void) {
    // 防止重复弹框
    static BOOL shown = NO;
    if (shown) return;
    shown = YES;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ 已停用" message:@"该软件已停用，请联系乌梢蛇。" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
    }];
    [alert addAction:exitAction];
    
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window && window.rootViewController) {
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    } else {
        exit(0);
    }
}

// ========== Toast提示 ==========
static void showToast(NSString *message, UIColor *color) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"声明" message:@"" preferredStyle:UIAlertControllerStyleAlert];
    
    // 标题字体加粗加大
    if (@available(iOS 13.0, *)) {
        NSMutableAttributedString *titleAttr = [[NSMutableAttributedString alloc] initWithString:@"声明" attributes:@{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:20],
            NSForegroundColorAttributeName: [UIColor blackColor]
        }];
        [alert setValue:titleAttr forKey:@"attributedTitle"];
    }
    
    // 正文文字加粗加大
    NSString *msg = @"该软件仅用于内部使用，切勿传播，勿用于非法用途，违者后果自负。\n\n软件有问题联系【乌梢蛇】处理，其他问题一概不知。";
    NSMutableAttributedString *msgAttr = [[NSMutableAttributedString alloc] initWithString:msg attributes:@{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:17],
        NSForegroundColorAttributeName: [UIColor blackColor]
    }];
    [alert setValue:msgAttr forKey:@"attributedMessage"];
    
    // 按钮
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        exit(0);
    }];
    UIAlertAction *agree = [UIAlertAction actionWithTitle:@"我已知晓" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (needActivate()) {
            showActivateAlert(window);
        }
    }];
    
    // 「我已知晓」红色
    if (@available(iOS 13.0, *)) {
        [agree setValue:[UIColor redColor] forKey:@"titleTextColor"];
    } else {
        alert.view.tintColor = [UIColor redColor];
    }
    
    [alert addAction:cancel];
    [alert addAction:agree];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ========== 原生激活码输入弹窗 ==========
static void showActivateAlert(UIWindow *window) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活验证" message:@"请输入激活码" preferredStyle:UIAlertControllerStyleAlert];
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
