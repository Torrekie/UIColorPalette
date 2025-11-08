//
//  AppDelegate.m
//  UIColorPalette
//
//  Created by Torrekie on 2025/11/4.
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [ViewController new];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
