//
//  AppDelegate.m
//  NKCamera
//
//  Created by nanoka____ on 2015/07/28.
//  Copyright (c) 2015年 nanoka____. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

/*========================================================
 ; AppDelegate
 ========================================================*/
@implementation AppDelegate

/*--------------------------------------------------------
 ; dealloc : 解放
 ;      in :
 ;     out :
 --------------------------------------------------------*/
-(void)dealloc {
    self.window = nil;
}

/*--------------------------------------------------------
 ; didFinishLaunchingWithOptions : 起動
 ;                            in : (UIApplication *)application
 ;                               : (NSDictionary *)launchOptions
 ;                           out :
 --------------------------------------------------------*/
-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *oViewController = [[ViewController alloc] init];
    self.window.rootViewController = oViewController;
    oViewController = nil;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
