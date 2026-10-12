//
//  LOGXBrand.h
//  LogeIsland — 落格Loge·灵动岛 v2.0（设置端共享头）
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSControlTableCell.h>
#import <Preferences/PSSwitchTableCell.h>

#import "LOGXConfig.h"
#import "LOGXConstants.h"
#import "LOGXLog.h"
#import "LOGXPath.h"

#define kLOGXColor [UIColor colorWithRed:0.242 green:0.486 blue:0.980 alpha:1.0]   // #3D7CFA

/// 标题键（PSSpecifier 常量在旧 SDK 头里可能缺失，这里自备）
#define LOGX_PS_KEY_KEY      @"key"
#define LOGX_PS_DEFAULTS_KEY @"defaults"
#define LOGX_PS_MIN_KEY      @"min"
#define LOGX_PS_MAX_KEY      @"max"
