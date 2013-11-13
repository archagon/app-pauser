//
//  APSettings.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/13/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import <Foundation/Foundation.h>

// I hate singletons, but this ain't no hoity toity corporate project.
@interface APSettings : NSObject
+ (id) settingForKeyPath:(NSString*)keyPath;
@end
