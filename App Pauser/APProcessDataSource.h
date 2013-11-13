//
//  APProcessDataSource.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/12/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface APProcessDataSource : NSObject <NSTableViewDataSource>

@property (nonatomic, retain, readonly) NSArray* applications; // KVO-observe me!
@property (nonatomic, retain) NSString* filter;

-(CGFloat) getCPUTimeForApplication:(NSRunningApplication*)application;
-(BOOL) suspend:(BOOL)suspend application:(NSRunningApplication*)application; // auto updates status

// status notifications aren't provided by the OS, so we have to be a little kludgy
-(BOOL) applicationIsSuspended:(NSRunningApplication*)application;
-(NSString*) applicationStatus:(NSRunningApplication*)application;
-(void) updateStatusForApplication:(NSRunningApplication*)application; // nil for all applications

@end
