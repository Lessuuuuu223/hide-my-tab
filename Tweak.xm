#import <UIKit/UIKit.h>

// ========== 你原来的移除Tab代码，完全保留，没有修改 ==========
%hook UITabBarController

- (void)viewDidLoad {
    %orig;
    
    // 延迟执行，等界面完全稳定
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSArray *vcs = self.viewControllers;
        if (!vcs || vcs.count <= 2) return;
        
        // 只保留前2个Tab
        NSArray *newVCs = [vcs subarrayWithRange:NSMakeRange(0, 2)];
        
        // 关键：先切到第0个Tab，再移除，避免选中被移除的Tab
        self.selectedIndex = 0;
        
        // 动画移除，减少闪退概率
        [self setViewControllers:newVCs animated:NO];
        
        // 清理TabBar按钮
        UITabBar *tabBar = self.tabBar;
        NSArray *items = tabBar.items;
        if (items.count > 2) {
            NSArray *newItems = [items subarrayWithRange:NSMakeRange(0, 2)];
            [tabBar setItems:newItems animated:NO];
        }
    });
}

// 不拦截 setSelectedIndex，避免启动时状态冲突
// 如果应用代码试图切换到不存在的Tab，系统会自动处理

%end


// ========== 新增的启动免责声明弹窗功能 ==========
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟1.5秒，等界面完全初始化，避免rootViewController还没准备好
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            // 兼容iOS13+的Scene机制，正确获取当前的KeyWindow
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
            // 兼容旧系统的KeyWindow获取
            if (!keyWindow) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                keyWindow = [UIApplication sharedApplication].keyWindow;
                #pragma clang diagnostic pop
            }
            
            // 如果rootViewController还没准备好，重试一次，避免崩溃
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
                        [self showDisclaimerAlert:retryWindow];
                    }
                });
                return;
            }
            
            [self showDisclaimerAlert:keyWindow];
        });
    });
}

// 弹出免责声明弹窗的核心方法
- (void)showDisclaimerAlert:(UIWindow *)window {
    NSString *msg = @"免责声明：该软件仅用于内部使用，请勿用于非法用途，违者后果自负，软件有问题联系乌梢蛇处理，其他问题一概不知。";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"免责声明"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    // 取消按钮：蓝色（Default样式），点击直接退出App
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        exit(0);
    }];
    
    // 同意按钮：红色（Destructive样式），点击继续进入App
    UIAlertAction *agreeAction = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // 什么都不做，正常继续运行App
    }];
    
    // 按钮顺序：左取消、右同意，符合用户操作习惯
    [alert addAction:cancelAction];
    [alert addAction:agreeAction];
    
    // 找到最顶层的ViewController，避免present失败
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

%end
