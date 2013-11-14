//
//  APProcessDataSource.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/12/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface APProcessDataSource : NSObject <NSTableViewDataSource>

@property (nonatomic, retain, readonly) NSArray* processIDs; // KVO-observe me!

@property (nonatomic, assign, readonly) NSInteger cpuTimeUpdateTick; // KVO-observe me!
@property (nonatomic, retain) NSString* filter;
@property (nonatomic, assign) BOOL showOnlyHighUsage;

-(NSString*) nameForProcess:(pid_t)processID;
-(NSImage*) imageForProcess:(pid_t)processID;
-(CGFloat) CPUTimeForProcess:(pid_t)processID;
-(CGFloat) energyForProcess:(pid_t)processID;

-(BOOL) processIsSuspended:(pid_t)processID;
-(NSString*) statusForProcess:(pid_t)processID;
-(void) updateStatusForProcess:(pid_t)processID; // -1 for all applications

-(BOOL) suspend:(BOOL)suspend process:(pid_t)processID; // auto updates status

@end
