#import <UIKit/UIKit.h>

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
