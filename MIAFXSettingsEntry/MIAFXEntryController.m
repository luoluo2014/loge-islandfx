//
//  MIAFXEntryController.m
//  MIAFXSettingsEntry
//
//  「设置」App 里的插件入口：一个 PSViewController 容器，把完整的调参界面
//  （MIAFXRootViewController）原样承载进来。这样既没有独立 App、没有桌面图标，
//  又保留了输入框 + 滑块 + 步进、实时小岛预览、素材/诊断跳转与底部署名。
//
//  省电设计：本页面只在用户主动打开系统设置时存在；离开页面时子控制器的
//  viewWillDisappear 会自动停止预览动画，不产生任何后台开销。
//

#import <Preferences/PSViewController.h>

#import "MIAFXRootViewController.h"

@interface MIAFXEntryController : PSViewController
@property (nonatomic, strong, nullable) MIAFXRootViewController *settingsController;
@end

@implementation MIAFXEntryController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"落格Loge·灵动岛";
    }
    return self;
}

- (instancetype)initForContentSize:(CGSize)contentSize {
    (void)contentSize;
    // iOS 14 之后 PSViewController 已移除 initForContentSize:，PreferenceLoader 仍会
    // 用这个入口实例化，因此这里实现它、但底层走标准 init，避免 unrecognized selector。
    self = [super init];
    if (self) {
        self.title = @"落格Loge·灵动岛";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"落格Loge·灵动岛";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    MIAFXRootViewController *settings = [[MIAFXRootViewController alloc] initWithNibName:nil bundle:nil];
    self.settingsController = settings;

    [self addChildViewController:settings];
    settings.view.frame = self.view.bounds;
    settings.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:settings.view];
    [settings didMoveToParentViewController:self];

    // 搜索栏原本挂在子控制器自己的 navigationItem 上；作为子控制器它不会显示，
    // 这里把它搬到父级 navigationItem，搜索回调仍由 MIAFXRootViewController 处理。
    if (settings.navigationItem.searchController != nil) {
        self.navigationItem.searchController = settings.navigationItem.searchController;
        self.definesPresentationContext = YES;
    }
}

@end
