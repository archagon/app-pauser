//
//  APSettings.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/13/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APSettings.h"

@interface APSettings ()
@property (nonatomic, retain) NSDictionary* settings;
@end

@implementation APSettings

+ (id) settingForKeyPath:(NSString*)key
{
    static dispatch_once_t once;
    static APSettings* sharedInstance;
    dispatch_once(&once, ^
    {
        sharedInstance = [[self alloc] init];
        sharedInstance.settings = nil;
        NSString* plistPath = [[NSBundle mainBundle] pathForResource:@"APSettings" ofType:@"plist"];
        sharedInstance.settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    });
    
    return [sharedInstance.settings valueForKeyPath:key];
}

@end
