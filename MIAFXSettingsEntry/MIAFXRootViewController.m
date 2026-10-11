//
//  MIAFXRootViewController.m
//  MIAFXPrefs
//

#import "MIAFXRootViewController.h"

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXDefaults.h"
#import "MIAFXFilzaLauncher.h"
#import "MIAFXNumberControlCell.h"
#import "MIAFXPath.h"
#import "MIAFXPreviewView.h"
#import "MIAFXSettingsCatalog.h"

#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdlib.h>

#pragma mark - 内部渲染结构

/// 一次要渲染的小节：来自某个分页，已过滤掉不可见项
@interface MIAFXRenderSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) NSArray<MIAFXSettingSpec *> *items;
@end

@implementation MIAFXRenderSection
@end

#pragma mark - 开关行

@interface MIAFXSwitchCell : UITableViewCell
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong, nullable) MIAFXSettingSpec *spec;
@property (nonatomic, copy, nullable) void (^onChange)(MIAFXSettingSpec *spec, BOOL value);
@end

@implementation MIAFXSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    _toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_toggle addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
    self.accessoryView = _toggle;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.detailTextLabel.numberOfLines = 0;
    self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    self.textLabel.numberOfLines = 0;
    return self;
}

- (void)valueChanged:(UISwitch *)sender {
    if (self.spec && self.onChange) self.onChange(self.spec, sender.isOn);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.spec = nil;
    self.onChange = nil;
}

@end

#pragma mark - 分段控件行

@interface MIAFXSegmentedCell : UITableViewCell
@property (nonatomic, strong) UISegmentedControl *segmented;
@property (nonatomic, strong) UILabel *detailInfoLabel;
@property (nonatomic, strong, nullable) MIAFXSettingSpec *spec;
@property (nonatomic, copy, nullable) void (^onChange)(MIAFXSettingSpec *spec, NSInteger index);
@end

@implementation MIAFXSegmentedCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.textLabel.numberOfLines = 0;
    self.textLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];

    UILabel *detailLabel = [self makeDetailLabel];
    [self.contentView addSubview:detailLabel];
    _detailInfoLabel = detailLabel;

    _segmented = [[UISegmentedControl alloc] initWithItems:@[]];
    _segmented.translatesAutoresizingMaskIntoConstraints = NO;
    [_segmented addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_segmented];

    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [detailLabel.topAnchor constraintEqualToAnchor:margins.topAnchor constant:4.0],
        [detailLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [detailLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_segmented.topAnchor constraintEqualToAnchor:detailLabel.bottomAnchor constant:8.0],
        [_segmented.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_segmented.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_segmented.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-8.0],
    ]];
    return self;
}

- (UILabel *)makeDetailLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (void)valueChanged:(UISegmentedControl *)sender {
    if (self.spec && self.onChange) self.onChange(self.spec, sender.selectedSegmentIndex);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.spec = nil;
    self.onChange = nil;
    [self.segmented removeAllSegments];
}

@end

#pragma mark - 值/动作行（disclosure）

@interface MIAFXValueCell : UITableViewCell
@end

@implementation MIAFXValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.textLabel.numberOfLines = 0;
    self.detailTextLabel.numberOfLines = 0;
    self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return self;
}

@end

#pragma mark - 分组切换条

@interface MIAFXCategoryBar : UIScrollView
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy, nullable) void (^onSelect)(NSUInteger index);
@property (nonatomic) NSUInteger selectedIndex;
- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated;
@end

@interface MIAFXCategoryBar ()
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@end

@implementation MIAFXCategoryBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _buttons = [NSMutableArray array];
    _selectedIndex = 0;
    self.showsHorizontalScrollIndicator = NO;
    self.alwaysBounceHorizontal = YES;
    self.backgroundColor = UIColor.clearColor;
    return self;
}

- (void)setTitles:(NSArray<NSString *> *)titles {
    _titles = titles;
    for (UIButton *button in self.buttons) [button removeFromSuperview];
    [self.buttons removeAllObjects];
    NSUInteger index = 0;
    for (NSString *title in titles) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = (NSInteger)index;
        [button setTitle:title forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        button.layer.cornerRadius = 14.0;
        button.layer.masksToBounds = YES;
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
        [self.buttons addObject:button];
        index += 1;
    }
    self.selectedIndex = MIN(self.selectedIndex, titles.count > 0 ? titles.count - 1 : 0);
    [self setNeedsLayout];
}

- (void)tapped:(UIButton *)sender {
    [self setSelectedIndex:(NSUInteger)sender.tag animated:YES];
    if (self.onSelect) self.onSelect((NSUInteger)sender.tag);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 16.0;
    CGFloat height = 30.0;
    CGFloat y = (self.bounds.size.height - height) / 2.0;
    NSUInteger index = 0;
    UIFont *font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    for (UIButton *button in self.buttons) {
        NSString *title = self.titles[index];
        CGFloat width = [title sizeWithAttributes:@{NSFontAttributeName: font}].width + 22.0;
        button.frame = CGRectMake(x, y, width, height);
        BOOL selected = (index == self.selectedIndex);
        button.backgroundColor = selected ? UIColor.systemBlueColor : UIColor.secondarySystemFillColor;
        [button setTitleColor:selected ? UIColor.whiteColor : UIColor.labelColor forState:UIControlStateNormal];
        x += width + 8.0;
        index += 1;
    }
    self.contentSize = CGSizeMake(x + 8.0, self.bounds.size.height);
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [self setSelectedIndex:selectedIndex animated:NO];
}

- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated {
    (void)animated;
    if (index >= self.titles.count) index = 0;
    _selectedIndex = index;
    [UIView animateWithDuration:0.15 animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];
    UIButton *button = index < self.buttons.count ? self.buttons[index] : nil;
    if (button) [self scrollRectToVisible:button.frame animated:YES];
}

@end

#pragma mark - 枚举选择列表

@interface MIAFXOptionListViewController : UITableViewController
@property (nonatomic, strong, nullable) MIAFXSettingSpec *spec;
@property (nonatomic, copy, nullable) void (^onSelect)(MIAFXSettingSpec *spec, NSInteger index);
@end

@implementation MIAFXOptionListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.spec.title ?: @"选项";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"option"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.spec.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    MIAFXSettingOption *option = self.spec.options[(NSUInteger)indexPath.row];
    cell.textLabel.text = option.title;
    cell.detailTextLabel.text = option.optionDescription;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    id current = [self.spec currentValue];
    cell.accessoryType = [option.value isEqual:current] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.onSelect) self.onSelect(self.spec, indexPath.row);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - 诊断页

@interface MIAFXDiagnosticsViewController : UITableViewController
@end

@interface MIAFXDiagnosticsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *rows;   // 每个元素：{title, value}
@property (nonatomic, copy) NSArray<NSString *> *pathRows;
@end

@implementation MIAFXDiagnosticsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"诊断";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"diag"];
    [self reloadData];
}

- (void)reloadData {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    MIAFXFilzaLauncher *launcher = [MIAFXFilzaLauncher sharedLauncher];

    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    [rows addObject:@{@"title": @"总开关", @"value": [config boolForKey:@"Global.Enabled"] ? @"已开启" : @"已关闭"}];
    NSArray<NSString *> *features = [[MIAFXSettingsCatalog sharedCatalog] activeFeatureTitles];
    [rows addObject:@{@"title": @"启用阶段", @"value": features.count > 0 ? [features componentsJoinedByString:@" · "] : @"无"}];
    NSInteger tier = [config integerForKey:@"Global.PerformanceTier"];
    [rows addObject:@{@"title": @"性能档位", @"value": tier == 0 ? @"节能" : (tier == 2 ? @"华丽" : @"均衡")}];
    NSInteger policy = [config integerForKey:@"Global.SleepPolicy"];
    NSString *policyText = policy == 1 ? @"降帧运行" : (policy == 2 ? @"常驻渲染" : @"智能暂停");
    [rows addObject:@{@"title": @"息屏策略", @"value": policyText}];
    [rows addObject:@{@"title": @"最高帧率", @"value": [NSString stringWithFormat:@"%ld fps", (long)[config integerForKey:@"Global.MaxFPS"]]}];
    [rows addObject:@{@"title": @"已启用 Metered 数量", @"value": [NSString stringWithFormat:@"%lu 项", (unsigned long)[[MIAFXSettingsCatalog sharedCatalog] settingCount]]}];

    NSDictionary *panic = [NSDictionary dictionaryWithContentsOfFile:MIAFXPanicPath()];
    NSInteger attempts = [panic[@"Attempts"] integerValue];
    NSString *attemptText = panic == nil ? @"无记录（未触发）" : [NSString stringWithFormat:@"%ld 次%@", (long)attempts, attempts >= 3 ? @"（已触发保护）" : @""];
    [rows addObject:@{@"title": @"连续启动计数", @"value": attemptText}];
    double lastStart = [panic[@"LastStart"] doubleValue];
    if (lastStart > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:lastStart];
        [rows addObject:@{@"title": @"最近一次启动", @"value": [NSString stringWithFormat:@"%@", date]}];
    }

    NSDictionary *diagnostics = [NSDictionary dictionaryWithContentsOfFile:MIAFXDiagnosticsPath()];
    if ([diagnostics isKindOfClass:NSDictionary.class] && diagnostics.count > 0) {
        NSArray<NSString *> *keys = [diagnostics.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in keys) {
            [rows addObject:@{@"title": key, @"value": [NSString stringWithFormat:@"%@", diagnostics[key]]}];
        }
    } else {
        [rows addObject:@{@"title": @"diagnostics.plist", @"value": @"暂无内容（后台尚未写入）"}];
    }

    self.rows = rows;
    self.pathRows = @[
        [NSString stringWithFormat:@"数据目录：%@", launcher.dataDirectory],
        [NSString stringWithFormat:@"配置文件：%@", launcher.configurationFilePath],
        [NSString stringWithFormat:@"panic 文件：%@", launcher.panicFilePath],
        [NSString stringWithFormat:@"诊断文件：%@", launcher.diagnosticsFilePath],
        [NSString stringWithFormat:@"日志：%@", launcher.logFilePath],
    ];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;   // 运行状态 / 路径 / 操作
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return (NSInteger)self.rows.count;
    if (section == 1) return (NSInteger)self.pathRows.count;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"运行状态" : (section == 1 ? @"关键路径" : @"操作");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"diag" forIndexPath:indexPath];
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.section == 0) {
        NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", row[@"value"]];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = self.pathRows[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.detailTextLabel.text = nil;
        NSArray<NSString *> *actions = @[@"重置启动保护计数", @"重新扫描素材", @"复制全部路径", @"Respring（重载 SpringBoard）"];
        cell.textLabel.text = actions[(NSUInteger)indexPath.row];
        return cell;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MIAFXFilzaLauncher *launcher = [MIAFXFilzaLauncher sharedLauncher];
    if (indexPath.section == 1) {
        NSString *line = self.pathRows[(NSUInteger)indexPath.row];
        NSString *value = [[line componentsSeparatedByString:@"："] lastObject];
        [launcher copyToPasteboard:value hint:@"路径已复制" fromViewController:self];
        return;
    }
    if (indexPath.section != 2) return;
    switch (indexPath.row) {
        case 0: [self resetProtection]; break;
        case 1: [self rescan]; break;
        case 2: [self copyAllPaths]; break;
        case 3: [launcher requestRespringFromViewController:self]; break;
        default: break;
    }
}

/// 等价实现：清掉 panic.plist 中的连续启动计数（与 MIAFXResetBootGuard 行为一致）
- (void)resetProtection {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"重置启动保护计数"
                                                                     message:@"将连续启动失败计数归零，让所有阶段重新参与渲染。继续？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        MIAFXEnsureDataDirectories(&error);
        NSDictionary *reset = @{ @"Attempts": @0, @"ResetAt": @([[NSDate date] timeIntervalSince1970]) };
        [reset writeToFile:MIAFXPanicPath() atomically:YES];
        [[MIAFXConfig sharedConfig] publishLiveState];
        notify_post(MIAFX_NOTIFY_RELOAD);
        [weakSelf reloadData];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已重置"
                                                                      message:@"连续启动计数已归零。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:done animated:YES completion:nil];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)rescan {
    MIAFXFilzaLauncher *launcher = [MIAFXFilzaLauncher sharedLauncher];
    BOOL ok = [launcher ensureDirectories];
    notify_post(MIAFX_NOTIFY_RESCAN);
    notify_post(MIAFX_NOTIFY_RELOAD);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已请求重新扫描"
                                                                  message:ok ? @"素材目录已就绪，并已通知后台重新扫描。" : @"通知已发出，但部分目录创建失败。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyAllPaths {
    NSString *all = [self.pathRows componentsJoinedByString:@"\n"];
    [[MIAFXFilzaLauncher sharedLauncher] copyToPasteboard:all hint:@"全部路径已复制" fromViewController:self];
}

@end

#pragma mark - 主控制器

static NSString *const kMIAFXSwitchCellIdentifier = @"MIAFX.Switch";
static NSString *const kMIAFXNumberCellIdentifier = @"MIAFX.Number";
static NSString *const kMIAFXSegmentedCellIdentifier = @"MIAFX.Segmented";
static NSString *const kMIAFXValueCellIdentifier = @"MIAFX.Value";

@interface MIAFXRootViewController () <UITableViewDataSource,
                                       UITableViewDelegate,
                                       UISearchResultsUpdating,
                                       UISearchControllerDelegate,
                                       UIDocumentPickerDelegate,
                                       MIAFXNumberControlCellDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) MIAFXPreviewView *previewView;
@property (nonatomic, strong) MIAFXCategoryBar *categoryBar;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, strong) NSArray<MIAFXSettingPage *> *pages;
@property (nonatomic, strong) NSArray<MIAFXRenderSection *> *renderSections;
@property (nonatomic, strong, nullable) NSArray<MIAFXSettingPage *> *searchResults;
@property (nonatomic, strong, nullable) MIAFXSettingPage *selectedPage;
@property (nonatomic, strong, nullable) MIAFXNumberControlCell *activeNumberCell;
@property (nonatomic) BOOL pendingReload;
@property (nonatomic, strong, nullable) NSURL *currentExportURL;
@property (nonatomic, copy, nullable) NSString *pendingImportSpecKey;
@end

@implementation MIAFXRootViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) return nil;
    _pages = [[MIAFXSettingsCatalog sharedCatalog] pages];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"落格Loge·灵动岛";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self buildTableView];
    [self buildSearchController];
    [self buildTableHeader];
    [self buildTableFooter];
    [self reloadSectionsForCurrentPage];

    [[MIAFXFilzaLauncher sharedLauncher] ensureDirectories];

    __weak typeof(self) weakSelf = self;
    [[MIAFXConfig sharedConfig] addObserver:^(NSDictionary<NSString *, id> *settings) {
        (void)settings;
        [weakSelf.previewView refresh];
        if (weakSelf.activeNumberCell != nil) {
            weakSelf.pendingReload = YES;
            return;
        }
        [weakSelf.tableView reloadData];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[MIAFXConfig sharedConfig] reload];
    [self reloadSectionsForCurrentPage];
    [self.previewView startAnimating];
    [self.previewView refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self flushActiveNumberCell];
    [self.previewView stopAnimating];
}

#pragma mark 界面搭建

- (void)buildTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 72.0;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [tableView registerClass:MIAFXSwitchCell.class forCellReuseIdentifier:kMIAFXSwitchCellIdentifier];
    [tableView registerClass:MIAFXNumberControlCell.class forCellReuseIdentifier:kMIAFXNumberCellIdentifier];
    [tableView registerClass:MIAFXSegmentedCell.class forCellReuseIdentifier:kMIAFXSegmentedCellIdentifier];
    [tableView registerClass:MIAFXValueCell.class forCellReuseIdentifier:kMIAFXValueCellIdentifier];
    self.tableView = tableView;
    [self.view addSubview:tableView];
}

- (void)buildSearchController {
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.delegate = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.hidesNavigationBarDuringPresentation = YES;
    search.searchBar.placeholder = @"搜索设置项、分组或 key";
    self.searchController = search;
    self.navigationItem.searchController = search;
    self.definesPresentationContext = YES;
}

- (void)buildTableHeader {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = 214.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
    header.backgroundColor = UIColor.clearColor;
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    MIAFXPreviewView *preview = [[MIAFXPreviewView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height - 46.0)];
    preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.previewView = preview;
    [header addSubview:preview];

    MIAFXCategoryBar *bar = [[MIAFXCategoryBar alloc] initWithFrame:CGRectMake(0.0, height - 44.0, width, 44.0)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (MIAFXSettingPage *page in self.pages) [titles addObject:page.title];
    bar.titles = titles;
    __weak typeof(self) weakSelf = self;
    bar.onSelect = ^(NSUInteger index) {
        [weakSelf selectPageAtIndex:index];
    };
    self.categoryBar = bar;
    [header addSubview:bar];

    self.tableView.tableHeaderView = header;
}

/// 署名区：作者与寄语。放在表尾，既不打扰调参，也让每个页面都能看到出处。
- (void)buildTableFooter {
    CGFloat width = MAX(CGRectGetWidth(self.view.bounds), 320.0);
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 96.0)];
    footer.backgroundColor = UIColor.clearColor;
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    nameLabel.text = @"落格Loge·灵动岛";
    nameLabel.font = [UIFont boldSystemFontOfSize:15.0];
    nameLabel.textColor = UIColor.secondaryLabelColor;
    nameLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *authorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    authorLabel.text = @"落格出品";
    authorLabel.font = [UIFont systemFontOfSize:13.0];
    authorLabel.textColor = UIColor.tertiaryLabelColor;
    authorLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *mottoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    mottoLabel.text = @"每一个插件都有他的灵魂";
    mottoLabel.font = [UIFont systemFontOfSize:13.0];
    mottoLabel.textColor = UIColor.tertiaryLabelColor;
    mottoLabel.textAlignment = NSTextAlignmentCenter;
    mottoLabel.numberOfLines = 0;

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    versionLabel.text = version.length > 0 ? [NSString stringWithFormat:@"版本 %@", version] : @"";
    versionLabel.font = [UIFont systemFontOfSize:12.0];
    versionLabel.textColor = UIColor.tertiaryLabelColor;
    versionLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, authorLabel, mottoLabel, versionLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 4.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:footer.topAnchor constant:18.0]
    ]];

    self.tableView.tableFooterView = footer;
}

#pragma mark 渲染数据

- (BOOL)isSearching {
    return self.searchController.active && self.searchController.searchBar.text.length > 0;
}

- (void)selectPageAtIndex:(NSUInteger)index {
    if (index >= self.pages.count) return;
    self.selectedPage = self.pages[index];
    [self.previewView refresh];
    [self reloadSectionsForCurrentPage];
    [self.tableView setContentOffset:CGPointMake(0.0, -self.tableView.adjustedContentInset.top) animated:NO];
}

- (void)reloadSectionsForCurrentPage {
    NSMutableArray<MIAFXRenderSection *> *sections = [NSMutableArray array];
    NSArray<MIAFXSettingPage *> *pages = [self isSearching] ? (self.searchResults ?: @[]) : @[self.selectedPage ?: self.pages.firstObject];
    for (MIAFXSettingPage *page in pages) {
        if (!page) continue;
        for (MIAFXSettingSection *section in page.sections) {
            NSMutableArray<MIAFXSettingSpec *> *items = [NSMutableArray array];
            for (MIAFXSettingSpec *spec in section.items) {
                if ([spec isVisibleNow]) [items addObject:spec];
            }
            if (items.count == 0) continue;
            MIAFXRenderSection *render = [[MIAFXRenderSection alloc] init];
            render.pageTitle = page.title;
            render.items = items;
            if ([self isSearching]) {
                render.title = [NSString stringWithFormat:@"%@ · %@", page.title, section.title];
            } else {
                render.title = section.title;
            }
            render.footer = section.footer.length > 0 ? section.footer : nil;
            [sections addObject:render];
        }
    }
    self.renderSections = sections;
    [self.tableView reloadData];
}

- (MIAFXSettingSpec *)specAtIndexPath:(NSIndexPath *)indexPath {
    MIAFXRenderSection *section = self.renderSections[(NSUInteger)indexPath.section];
    return section.items[(NSUInteger)indexPath.row];
}

- (void)reloadAllData {
    [[MIAFXConfig sharedConfig] reload];
    [self.previewView refresh];
    [self reloadSectionsForCurrentPage];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)self.renderSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)self.renderSections[(NSUInteger)section].items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return self.renderSections[(NSUInteger)section].title;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return self.renderSections[(NSUInteger)section].footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MIAFXSettingSpec *spec = [self specAtIndexPath:indexPath];
    switch (spec.kind) {
        case MIAFXSettingKindNumber: {
            MIAFXNumberControlCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXNumberCellIdentifier forIndexPath:indexPath];
            cell.controlDelegate = self;
            [cell configureWithSpec:spec];
            return cell;
        }
        case MIAFXSettingKindSwitch:
        case MIAFXSettingKindFeatureFlag: {
            MIAFXSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXSwitchCellIdentifier forIndexPath:indexPath];
            cell.spec = spec;
            cell.textLabel.text = spec.title;
            cell.detailTextLabel.text = [self detailLineForSpec:spec];
            cell.toggle.on = [spec currentBool];
            __weak typeof(self) weakSelf = self;
            cell.onChange = ^(MIAFXSettingSpec *changed, BOOL value) {
                [weakSelf handleBoolChangeForSpec:changed value:value];
            };
            return cell;
        }
        case MIAFXSettingKindEnum: {
            if (spec.enumUsesSegmentedControl) {
                MIAFXSegmentedCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXSegmentedCellIdentifier forIndexPath:indexPath];
                cell.spec = spec;
                cell.textLabel.text = spec.title;
                cell.detailInfoLabel.text = [self detailLineForSpec:spec];
                [cell.segmented removeAllSegments];
                NSUInteger index = 0;
                for (MIAFXSettingOption *option in spec.options) {
                    [cell.segmented insertSegmentWithTitle:option.title atIndex:index animated:NO];
                    index += 1;
                }
                cell.segmented.selectedSegmentIndex = [self indexOfCurrentValueInSpec:spec];
                __weak typeof(self) weakSelf = self;
                cell.onChange = ^(MIAFXSettingSpec *changed, NSInteger selected) {
                    [weakSelf handleEnumSelectionForSpec:changed index:selected];
                };
                return cell;
            }
            MIAFXValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXValueCellIdentifier forIndexPath:indexPath];
            cell.textLabel.text = spec.title;
            cell.textLabel.textColor = UIColor.labelColor;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n当前：%@\n%@",
                                         spec.specDescription ?: @"",
                                         [spec valueDisplayString],
                                         [spec rangeDescriptionString]];
            return cell;
        }
        case MIAFXSettingKindText:
        case MIAFXSettingKindPath: {
            MIAFXValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXValueCellIdentifier forIndexPath:indexPath];
            cell.textLabel.text = spec.title;
            cell.textLabel.textColor = UIColor.labelColor;
            NSString *value = [spec valueDisplayString];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n当前：%@", spec.specDescription ?: @"", value];
            return cell;
        }
        case MIAFXSettingKindAction: {
            MIAFXValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kMIAFXValueCellIdentifier forIndexPath:indexPath];
            cell.textLabel.text = spec.title;
            cell.detailTextLabel.text = spec.specDescription;
            cell.textLabel.textColor = UIColor.systemBlueColor;
            return cell;
        }
    }
    UITableViewCell *fallback = [tableView dequeueReusableCellWithIdentifier:kMIAFXValueCellIdentifier forIndexPath:indexPath];
    fallback.textLabel.text = spec.title;
    return fallback;
}

- (NSString *)detailLineForSpec:(MIAFXSettingSpec *)spec {
    NSString *description = spec.specDescription ?: @"";
    NSString *range = [spec rangeDescriptionString];
    if (range.length > 0) return [NSString stringWithFormat:@"%@\n%@", description, range];
    return description;
}

- (NSInteger)indexOfCurrentValueInSpec:(MIAFXSettingSpec *)spec {
    id current = [spec currentValue];
    NSUInteger index = 0;
    for (MIAFXSettingOption *option in spec.options) {
        if ([option.value isEqual:current]) return (NSInteger)index;
        index += 1;
    }
    NSInteger numeric = [current integerValue];
    if (numeric >= 0 && (NSUInteger)numeric < spec.options.count) return numeric;
    return NSNotFound;
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MIAFXSettingSpec *spec = [self specAtIndexPath:indexPath];
    switch (spec.kind) {
        case MIAFXSettingKindEnum:
            [self presentOptionsForSpec:spec fromIndexPath:indexPath];
            break;
        case MIAFXSettingKindText:
            [self presentTextEditorForSpec:spec];
            break;
        case MIAFXSettingKindPath:
            [self presentPathActionsForSpec:spec fromIndexPath:indexPath];
            break;
        case MIAFXSettingKindAction:
            [self performActionWithIdentifier:spec.actionIdentifier ?: @""];
            break;
        default:
            break;
    }
}

#pragma mark 交互：开关 / 枚举 / 文本 / 路径

- (void)handleBoolChangeForSpec:(MIAFXSettingSpec *)spec value:(BOOL)value {
    MIAFXSettingsCatalog *catalog = [MIAFXSettingsCatalog sharedCatalog];
    if (spec.kind == MIAFXSettingKindFeatureFlag) {
        [catalog stageFeatureBit:spec.featureBit enabled:value];
    } else {
        [catalog stageBool:value forSpec:spec];
    }
    [self commitAndRefresh];
}

- (void)handleEnumSelectionForSpec:(MIAFXSettingSpec *)spec index:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= spec.options.count) return;
    MIAFXSettingOption *option = spec.options[(NSUInteger)index];
    [[MIAFXSettingsCatalog sharedCatalog] stageObject:option.value forSpec:spec];
    [self commitAndRefresh];
}

- (void)presentOptionsForSpec:(MIAFXSettingSpec *)spec fromIndexPath:(NSIndexPath *)indexPath {
    if (spec.enumUsesActionSheet) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:spec.title
                                                                      message:spec.specDescription
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
        for (MIAFXSettingOption *option in spec.options) {
            UIAlertAction *action = [UIAlertAction actionWithTitle:option.title
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *sender) {
                [self handleEnumSelectionForSpec:spec index:[self indexOfOptionWithTitle:sender.title inSpec:spec]];
            }];
            if ([option.value isEqual:[spec currentValue]]) {
                [sheet addAction:action];
                sheet.preferredAction = action;
            } else {
                [sheet addAction:action];
            }
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        if (sheet.popoverPresentationController) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            sheet.popoverPresentationController.sourceView = cell.contentView ?: self.view;
            sheet.popoverPresentationController.sourceRect = cell.contentView.bounds;
        }
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }
    MIAFXOptionListViewController *list = [[MIAFXOptionListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    list.spec = spec;
    __weak typeof(self) weakSelf = self;
    list.onSelect = ^(MIAFXSettingSpec *changed, NSInteger index) {
        [weakSelf handleEnumSelectionForSpec:changed index:index];
    };
    [self.navigationController pushViewController:list animated:YES];
}

- (NSInteger)indexOfOptionWithTitle:(NSString *)title inSpec:(MIAFXSettingSpec *)spec {
    NSUInteger index = 0;
    for (MIAFXSettingOption *option in spec.options) {
        if ([option.title isEqualToString:title]) return (NSInteger)index;
        index += 1;
    }
    return NSNotFound;
}

- (void)presentTextEditorForSpec:(MIAFXSettingSpec *)spec {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:spec.title
                                                                  message:spec.specDescription
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [spec currentValue];
        textField.placeholder = @"留空表示使用默认值";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        [[MIAFXSettingsCatalog sharedCatalog] stageObject:text forSpec:spec];
        [weakSelf commitAndRefresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 路径：可手动输入、从「文件」App 选取、在 Filza 中打开、复制、清除
- (void)presentPathActionsForSpec:(MIAFXSettingSpec *)spec fromIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:spec.title
                                                                  message:spec.specDescription
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动输入路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentPathEditorForSpec:spec];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从「文件」中选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentDocumentPickerImportingForSpec:spec];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"在 Filza 中打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *path = [weakSelf specCurrentString:spec];
        NSString *target = path.length > 0 ? path : [[MIAFXFilzaLauncher sharedLauncher] dataDirectory];
        [[MIAFXFilzaLauncher sharedLauncher] openPath:target title:spec.title fromViewController:weakSelf];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制当前路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *path = [weakSelf specCurrentString:spec];
        [[MIAFXFilzaLauncher sharedLauncher] copyToPasteboard:path hint:@"路径已复制" fromViewController:weakSelf];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[MIAFXSettingsCatalog sharedCatalog] stageObject:@"" forSpec:spec];
        [weakSelf commitAndRefresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)specCurrentString:(MIAFXSettingSpec *)spec {
    id value = [spec currentValue];
    if ([value isKindOfClass:NSString.class]) return value;
    return value ? [NSString stringWithFormat:@"%@", value] : @"";
}

- (void)presentPathEditorForSpec:(MIAFXSettingSpec *)spec {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:spec.title
                                                                  message:@"请输入完整路径，例如 var/mobile/Library/MIAFX/Videos/demo.mp4"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [self specCurrentString:spec];
        textField.placeholder = @"文件路径";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        [[MIAFXSettingsCatalog sharedCatalog] stageObject:text forSpec:spec];
        [weakSelf commitAndRefresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark 数值控件回调

- (void)numberCell:(MIAFXNumberControlCell *)cell didChangeValue:(double)value continuous:(BOOL)continuous {
    if (!cell.spec) return;
    [[MIAFXSettingsCatalog sharedCatalog] stageDouble:value forSpec:cell.spec];
    [self.previewView refresh];
    if (!continuous) [self scheduleCommit];
}

- (void)numberCell:(MIAFXNumberControlCell *)cell didCommitValue:(double)value {
    if (!cell.spec) return;
    [[MIAFXSettingsCatalog sharedCatalog] stageDouble:value forSpec:cell.spec];
    [self commitAndRefresh];
}

- (void)numberCellDidBeginEditing:(MIAFXNumberControlCell *)cell {
    self.activeNumberCell = cell;
}

- (void)numberCellDidEndEditing:(MIAFXNumberControlCell *)cell {
    if (self.activeNumberCell == cell) self.activeNumberCell = nil;
    [self commitAndRefresh];
    if (self.pendingReload) {
        self.pendingReload = NO;
        [self reloadSectionsForCurrentPage];
    }
}

- (void)scheduleCommit {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self commitAndRefresh];
    });
}

- (void)flushActiveNumberCell {
    [self.activeNumberCell flushPendingCommit];
    self.activeNumberCell = nil;
}

/// 需求 8：统一通过 MIAFXConfig save: 落盘（内部会发布 live state 并 post reload notify）
- (void)commitAndRefresh {
    NSError *error = nil;
    BOOL ok = [[MIAFXSettingsCatalog sharedCatalog] commitWithError:&error];
    if (!ok) {
        [self showErrorAlert:error.localizedDescription ?: @"未知错误"];
    }
    [self.previewView refresh];
    if (self.activeNumberCell == nil) {
        [self reloadSectionsForCurrentPage];
    } else {
        self.pendingReload = YES;
    }
}

#pragma mark 搜索

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    self.searchResults = [[MIAFXSettingsCatalog sharedCatalog] filteredPagesForQuery:query];
    [self reloadSectionsForCurrentPage];
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    (void)searchController;
    self.searchResults = nil;
    [self reloadSectionsForCurrentPage];
}

#pragma mark 动作分发

- (void)performActionWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return;
    MIAFXSettingsCatalog *catalog = [MIAFXSettingsCatalog sharedCatalog];
    MIAFXSettingPreset *preset = [catalog presetForActionIdentifier:identifier];
    if (preset) {
        [self confirmPreset:preset];
        return;
    }
    if ([identifier hasPrefix:@"reset.page."]) {
        NSString *pageIdentifier = [identifier substringFromIndex:@"reset.page.".length];
        MIAFXSettingPage *page = [catalog pageWithIdentifier:pageIdentifier];
        if (page) [self confirmResetPage:page];
        return;
    }
    if ([identifier isEqualToString:@"reset.all"]) {
        [self confirmResetAll];
        return;
    }
    if ([identifier isEqualToString:MIAFXActionDiagnostics]) {
        MIAFXDiagnosticsViewController *diagnostics = [[MIAFXDiagnosticsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:diagnostics animated:YES];
        return;
    }
    MIAFXFilzaLauncher *launcher = [MIAFXFilzaLauncher sharedLauncher];
    if ([identifier isEqualToString:MIAFXActionFilzaVideos]) {
        [launcher openLocation:MIAFXFilzaLocationVideos fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionFilzaMasks]) {
        [launcher openLocation:MIAFXFilzaLocationMasks fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionFilzaCustomOrbits]) {
        [launcher openLocation:MIAFXFilzaLocationCustomOrbits fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionFilzaPresets]) {
        [launcher openLocation:MIAFXFilzaLocationPresets fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionFilzaLogs]) {
        [launcher openLocation:MIAFXFilzaLocationLogs fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionFilzaConfiguration]) {
        [launcher openLocation:MIAFXFilzaLocationConfiguration fromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionExportConfiguration]) {
        [self confirmExport];
    } else if ([identifier isEqualToString:MIAFXActionImportConfiguration]) {
        [self presentDocumentPickerForImport];
    } else if ([identifier isEqualToString:MIAFXActionShareConfiguration]) {
        [self shareConfigurationFile];
    } else if ([identifier isEqualToString:MIAFXActionRespring]) {
        [launcher requestRespringFromViewController:self];
    } else if ([identifier isEqualToString:MIAFXActionResetProtection]) {
        [self resetProtectionCounter];
    } else if ([identifier isEqualToString:MIAFXActionRescanAssets]) {
        [self rescanAssets];
    } else if ([identifier isEqualToString:MIAFXActionOpenSystemSettings]) {
        [launcher openSystemSettingsFromViewController:self];
    }
}

#pragma mark 预设 / 重置

- (void)confirmPreset:(MIAFXSettingPreset *)preset {
    NSString *message = [NSString stringWithFormat:@"将写入 %lu 个参数并覆盖它们当前的取值。\n\n%@",
                         (unsigned long)preset.values.count,
                         preset.presetDescription ?: @""];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"应用预设：%@", preset.title]
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSError *error = nil;
        BOOL ok = [[MIAFXSettingsCatalog sharedCatalog] applyPreset:preset error:&error];
        if (!ok) {
            [weakSelf showErrorAlert:error.localizedDescription ?: @"写入失败"];
            return;
        }
        [weakSelf.previewView refresh];
        [weakSelf reloadSectionsForCurrentPage];
        [weakSelf showNotice:[NSString stringWithFormat:@"已应用「%@」预设", preset.title]];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)confirmResetPage:(MIAFXSettingPage *)page {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"恢复「%@」默认", page.title]
                                                                    message:@"该分组内的全部参数将被恢复为出厂值，其它分组不受影响。"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[MIAFXSettingsCatalog sharedCatalog] resetPage:page];
        [weakSelf commitAndRefresh];
        [weakSelf showNotice:[NSString stringWithFormat:@"「%@」已恢复默认", page.title]];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)confirmResetAll {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"恢复全部默认"
                                                                    message:@"所有参数都会恢复出厂值，包含预设、路径与开关状态。"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"全部恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[MIAFXSettingsCatalog sharedCatalog] resetAll];
        [weakSelf commitAndRefresh];
        [weakSelf showNotice:@"已全部恢复默认"];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)resetProtectionCounter {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"重置启动保护计数"
                                                                    message:@"将 panic.plist 中的连续启动计数归零。"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error = nil;
        MIAFXEnsureDataDirectories(&error);
        NSDictionary *reset = @{ @"Attempts": @0, @"ResetAt": @([[NSDate date] timeIntervalSince1970]) };
        [reset writeToFile:MIAFXPanicPath() atomically:YES];
        notify_post(MIAFX_NOTIFY_RELOAD);
        [weakSelf showNotice:@"保护计数已重置"];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)rescanAssets {
    BOOL ok = [[MIAFXFilzaLauncher sharedLauncher] ensureDirectories];
    notify_post(MIAFX_NOTIFY_RESCAN);
    [[MIAFXConfig sharedConfig] publishLiveState];
    notify_post(MIAFX_NOTIFY_RELOAD);
    [self showNotice:ok ? @"已请求重新扫描素材" : @"已请求重新扫描，但部分目录创建失败"];
}

#pragma mark 导入 / 导出

- (NSString *)exportFilePath {
    [[MIAFXFilzaLauncher sharedLauncher] ensureDirectories];
    NSString *name = [NSString stringWithFormat:@"MIAFX-settings-%ld.plist", (long)(NSInteger)[[NSDate date] timeIntervalSince1970]];
    return [[[MIAFXFilzaLauncher sharedLauncher] presetsDirectory] stringByAppendingPathComponent:name];
}

- (nullable NSURL *)writeConfigurationSnapshot {
    NSData *data = [[MIAFXSettingsCatalog sharedCatalog] exportConfigurationData];
    if (data == nil) return nil;
    NSString *path = [self exportFilePath];
    NSError *error = nil;
    BOOL ok = [data writeToFile:path options:0 error:&error];
    if (!ok) {
        [self showErrorAlert:error.localizedDescription ?: @"无法写出配置文件"];
        return nil;
    }
    self.currentExportURL = [NSURL fileURLWithPath:path];
    return self.currentExportURL;
}

- (void)confirmExport {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导出当前配置"
                                                                  message:@"导出的 plist 可以稍后从本机任意位置导入回来。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"保存到「文件」" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf exportViaDocumentPicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"通过分享发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf shareConfigurationFile];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)exportViaDocumentPicker {
    NSURL *url = [self writeConfigurationSnapshot];
    if (!url) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)shareConfigurationFile {
    NSURL *url = [self writeConfigurationSnapshot];
    if (!url) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)presentDocumentPickerForImport {
    UTType *plist = [UTType typeWithIdentifier:@"com.apple.property-list"];
    UTType *data = [UTType typeWithIdentifier:@"public.data"];
    UTType *item = [UTType typeWithIdentifier:@"public.item"];
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    if (plist) [types addObject:plist];
    if (data) [types addObject:data];
    if (item) [types addObject:item];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentDocumentPickerImportingForSpec:(MIAFXSettingSpec *)spec {
    self.currentExportURL = nil;
    UTType *movie = [UTType typeWithIdentifier:@"public.movie"];
    UTType *image = [UTType typeWithIdentifier:@"public.image"];
    UTType *item = [UTType typeWithIdentifier:@"public.item"];
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    if (movie) [types addObject:movie];
    if (image) [types addObject:image];
    if (item) [types addObject:item];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    self.pendingImportSpecKey = spec.key;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *targetKey = self.pendingImportSpecKey;
    self.pendingImportSpecKey = nil;
    if (targetKey.length > 0) {
        MIAFXSettingSpec *spec = [self specForKey:targetKey];
        NSString *path = url.path;
        if (spec && path.length > 0) {
            [[MIAFXSettingsCatalog sharedCatalog] stageObject:path forSpec:spec];
            [self commitAndRefresh];
            [self showNotice:[NSString stringWithFormat:@"已写入 %@", spec.title]];
        }
        return;
    }
    NSError *error = nil;
    NSInteger count = [[MIAFXSettingsCatalog sharedCatalog] importConfigurationFromURL:url error:&error];
    if (count < 0) {
        [self showErrorAlert:error.localizedDescription ?: @"无法解析该 plist"];
        return;
    }
    [self commitAndRefresh];
    [self showNotice:[NSString stringWithFormat:@"已导入 %ld 个参数", (long)count]];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (nullable MIAFXSettingSpec *)specForKey:(NSString *)key {
    for (MIAFXSettingPage *page in self.pages) {
        for (MIAFXSettingSection *section in page.sections) {
            for (MIAFXSettingSpec *spec in section.items) {
                if ([spec.key isEqualToString:key]) return spec;
            }
        }
    }
    return nil;
}

#pragma mark 通用提示

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"出错了"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showNotice:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"完成"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark 深链

- (BOOL)handleOpenURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"miafx"]) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *pageIdentifier = [self queryValueForKey:@"page" inURL:url];
    if (host.length > 0 && ![host isEqualToString:@"settings"] && ![host isEqualToString:@"open"]) host = @"settings";
    [[MIAFXConfig sharedConfig] reload];
    NSUInteger index = 0;
    if (pageIdentifier.length > 0) {
        NSUInteger found = [self indexOfPageWithIdentifier:pageIdentifier];
        index = (found == NSNotFound) ? 0 : found;
    }
    if (self.navigationController.topViewController != self) {
        [self.navigationController popToRootViewControllerAnimated:NO];
    }
    [self.categoryBar setSelectedIndex:index animated:NO];
    [self selectPageAtIndex:index];
    [self.previewView startAnimating];
    return YES;
}

- (NSUInteger)indexOfPageWithIdentifier:(NSString *)identifier {
    NSUInteger index = 0;
    for (MIAFXSettingPage *page in self.pages) {
        if ([page.identifier isEqualToString:identifier]) return index;
        index += 1;
    }
    return NSNotFound;
}

- (nullable NSString *)queryValueForKey:(NSString *)key inURL:(NSURL *)url {
    NSString *query = url.query;
    if (query.length == 0) return nil;
    NSArray<NSString *> *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray<NSString *> *pieces = [pair componentsSeparatedByString:@"="];
        if (pieces.count == 2 && [pieces[0] isEqualToString:key]) {
            return [pieces[1] stringByRemovingPercentEncoding];
        }
    }
    return nil;
}

@end
