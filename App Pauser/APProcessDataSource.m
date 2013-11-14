//
//  APProcessDataSource.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/12/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APProcessDataSource.h"
#import "APBSDProcessList.h"

@interface APProcessDataSource ()

// We have 2 ways to get active processes: KVO-observing the NSWorkspace,
// and polling BSD. With the first, we simply use the provided array.
// With the last, we replace our existing array, but only with the PIDs
// that aren't given by the NSWorkspace.

@property (nonatomic, retain, readwrite) NSArray* processIDs; // combined, sorted, filtered list
@property (nonatomic, retain) APBSDProcessList* BSDProcessList;
@property (nonatomic, retain) NSMutableDictionary* processIDsToApplications;

@property (nonatomic, retain) NSMutableDictionary* currentProcessIDsToCPU;
@property (nonatomic, retain) NSMutableDictionary* processIDsToEnergy;
@property (nonatomic, assign) CGFloat totalEnergy;

@property (nonatomic, retain) NSArray* cachedSortDescriptors;

@property (nonatomic, retain) NSTimer* CPUUpdateTimer;
@property (nonatomic, assign, readwrite) NSInteger cpuTimeUpdateTick;

@property (nonatomic, retain) NSRegularExpression* psRegex;
@property (nonatomic, retain) NSRegularExpression* psCPURegex;

-(void) updateProcessIDs;

@end

@implementation APProcessDataSource

-(void) dealloc
{
    [[NSWorkspace sharedWorkspace] removeObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications))];
    [self.CPUUpdateTimer invalidate];
}

-(id) init
{
    self = [super init];
    if (self)
    {
        self.processIDs = [NSArray array];
        self.processIDsToApplications = [NSMutableDictionary dictionary];
        self.currentProcessIDsToCPU = [NSMutableDictionary dictionary];
        self.processIDsToEnergy = [NSMutableDictionary dictionary];
        
        self.BSDProcessList = [[APBSDProcessList alloc] init];
        [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications)) options:NSKeyValueObservingOptionInitial context:NULL];

        self.psRegex = [NSRegularExpression regularExpressionWithPattern:@"\\n[^\\n]*?\\s*(\\d+)\\s+([a-zA-Z]+)\\s*\\n"
                                                                               options:0
                                                                                 error:NULL];
        self.psCPURegex = [NSRegularExpression regularExpressionWithPattern:@"\\n[^\\n]*?\\s*(\\d+)\\s+(\\d+.\\d+)\\s*\\n"
                                                                    options:0
                                                                      error:NULL];
        
        self.CPUUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(pollCPU) userInfo:nil repeats:YES];
    }
    return self;
}

-(void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    if (object == [NSWorkspace sharedWorkspace])
    {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(runningApplications))])
        {
            [self updateProcessIDs];
        }
    }
}

-(void) updateProcessIDs
{
    NSArray* runningApplications = [[NSWorkspace sharedWorkspace] runningApplications];
    NSMutableArray* processIDs = [NSMutableArray array];
    self.processIDsToApplications = [NSMutableDictionary dictionary];
    
    // first, gather the NSWorkspace applications
    for (NSRunningApplication* application in runningApplications)
    {
        [processIDs addObject:@([application processIdentifier])];
        self.processIDsToApplications[@([application processIdentifier])] = application;
    }
    
    [self.BSDProcessList refreshProcessList];
    NSArray* BSDprocessIDs = [self.BSDProcessList processIDs];
    
    // next, gather the BSD processes
    for (NSNumber* processID in BSDprocessIDs)
    {
        if (!self.processIDsToApplications[processID])
        {
            [processIDs addObject:processID];
        }
    }
    
    NSArray* filteredApplications = [self filter:processIDs withFilter:self.filter];
    NSArray* sortedApplications = [self sort:filteredApplications withSortDescriptors:self.cachedSortDescriptors];
    
    for (NSNumber* processID in sortedApplications)
    {
        if (!self.processIDsToEnergy[processID])
        {
            self.processIDsToEnergy[processID] = @0;
        }
    }
    
    self.processIDs = sortedApplications;
}

-(void) pollCPU
{
    self.currentProcessIDsToCPU = [NSMutableDictionary dictionary];
    
    for (NSNumber* processID in self.processIDs)
    {
        self.currentProcessIDsToCPU[processID] = @0;
    }
    
    // launch ps task
    NSTask* statusTask = [[NSTask alloc] init];
    [statusTask setLaunchPath:@"/bin/ps"];
    NSArray* arguments = arguments = [NSArray arrayWithObjects:@"aux", @"-o", @"pid,%cpu", nil];
    [statusTask setArguments:arguments];
    statusTask.standardOutput = [NSPipe pipe];
    [statusTask launch];
    [statusTask waitUntilExit];
    
    // make sure exit status is OK
    int terminationStatus = [statusTask terminationStatus];
    NSAssert(terminationStatus == 0, @"ps returned with a termination status of %d", terminationStatus);
    
    // capture output data from pipe
    NSData* outputData = [[statusTask.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString* outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    CGFloat totalMeasuredLoad = 0;
    
    // process output data
    NSArray* matches = [self.psCPURegex matchesInString:outputString options:0 range:NSMakeRange(0, [outputString length])];
    for (NSTextCheckingResult* match in matches)
    {
        NSString* processIDString = [outputString substringWithRange:[match rangeAtIndex:1]];
        pid_t processID = [processIDString intValue];
        NSNumber* processIDKey = @(processID);
        NSString* cpu = [outputString substringWithRange:[match rangeAtIndex:2]];
        CGFloat cpuValue = [cpu doubleValue];
        
        if (self.currentProcessIDsToCPU[processIDKey])
        {
            self.currentProcessIDsToCPU[processIDKey] = @(cpuValue);
            
            if (self.processIDsToEnergy[processIDKey])
            {
                self.processIDsToEnergy[processIDKey] = @([self.processIDsToEnergy[processIDKey] doubleValue] + cpuValue);
            }
            else
            {
                self.processIDsToEnergy[processIDKey] = @0;
            }
            
            totalMeasuredLoad += cpuValue;
        }
    }
    
    self.totalEnergy += 100; // TODO: this isn't really accurate for dual cores; should be 200?
    self.cpuTimeUpdateTick++;
}

//-(void) pollCPUAsync
//{
//    [self pollAllProcesses];
//    
//    // launch ps task
//    NSTask* statusTask = [[NSTask alloc] init];
//    [statusTask setLaunchPath:@"/bin/ps"];
//    NSArray* arguments = arguments = [NSArray arrayWithObjects:@"aux", @"-o", @"pid,%cpu", nil];
//    [statusTask setArguments:arguments];
//    statusTask.standardOutput = [NSPipe pipe];
//    [statusTask launch];
//    
//    [[statusTask.standardOutput fileHandleForReading] setReadabilityHandler:^(NSFileHandle* handle)
//    {
//        // make sure exit status is OK
////        int terminationStatus = [statusTask terminationStatus];
////        NSAssert(terminationStatus == 0, @"ps returned with a termination status of %d", terminationStatus);
//        
//        // capture output data from pipe
//        NSData* outputData = [handle readDataToEndOfFile];
//        NSString* outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
//        CGFloat totalMeasuredLoad = 0;
//        
//        self.currentProcessIDsToCPU = [NSMutableDictionary dictionary];
//        
//        for (NSRunningApplication* application in self.runningApplications)
//        {
//            NSString* pidKey = [NSString stringWithFormat:@"%d", [application processIdentifier]];
//            self.currentProcessIDsToCPU[pidKey] = @"0.0";
//        }
//        
//        // process output data
//        NSArray* matches = [self.psCPURegex matchesInString:outputString options:0 range:NSMakeRange(0, [outputString length])];
//        for (NSTextCheckingResult* match in matches)
//        {
//            NSString* processID = [outputString substringWithRange:[match rangeAtIndex:1]];
//            NSString* cpu = [outputString substringWithRange:[match rangeAtIndex:2]];
//            
//            if (self.currentProcessIDsToCPU[processID])
//            {
//                CGFloat cpuValue = [cpu doubleValue];
//                
//                self.currentProcessIDsToCPU[processID] = cpu;
//                
//                if (self.processIDsToEnergy[processID])
//                {
//                    self.processIDsToEnergy[processID] = @([self.processIDsToEnergy[processID] doubleValue] + cpuValue);
//                }
//                else
//                {
//                    self.processIDsToEnergy[processID] = @0;
//                }
//                
//                totalMeasuredLoad += cpuValue;
//            }
//        }
//        
//        self.totalEnergy += 100;
//        
//        dispatch_sync(dispatch_get_main_queue(), ^
//        {
////            self.cpuTimeUpdateTick++;
//        });
//    }];
//}

-(NSString*) nameForProcess:(pid_t)processID
{
    if (self.processIDsToApplications[@(processID)])
    {
        return [self.processIDsToApplications[@(processID)] localizedName];
    }
    else
    {
        return [self.BSDProcessList nameForProcessID:processID];
    }
}

-(NSImage*) imageForProcess:(pid_t)processID
{
    if (self.processIDsToApplications[@(processID)])
    {
        return [self.processIDsToApplications[@(processID)] icon];
    }
    else
    {
        return nil;
    }
}

-(CGFloat) CPUTimeForProcess:(pid_t)processID
{
    return [self.currentProcessIDsToCPU[@(processID)] doubleValue];
}

-(CGFloat) energyForProcess:(pid_t)processID
{
    if (self.totalEnergy == 0)
    {
        return 0;
    }
    else
    {
        return [self.processIDsToEnergy[@(processID)] doubleValue] / self.totalEnergy;
    }
}

-(BOOL) suspend:(BOOL)suspend process:(pid_t)processID
{
    NSString* processIDString = [NSString stringWithFormat:@"%d", processID];
    NSString* command;
    
    if (!suspend)
    {
        command = @"-CONT";
    }
    else
    {
        command = @"-STOP";
    }
    
    NSTask* resumeTask = [[NSTask alloc] init];
    [resumeTask setLaunchPath:@"/bin/kill"];
    NSArray* arguments = [NSArray arrayWithObjects:command, processIDString, nil];
    [resumeTask setArguments:arguments];
    [resumeTask launch];
    [resumeTask waitUntilExit];
    
    [self updateStatusForProcess:processID];
    
    if (suspend == [self processIsSuspended:processID])
    {
        return YES;
    }
    else
    {
        NSAssert(NO, @"application could not suspend");
        return NO;
    }
}

-(BOOL) processIsSuspended:(pid_t)processID
{
    return ([[[self statusForProcess:processID] substringToIndex:1] isEqualToString:@"T"]);
}

-(NSString*) statusForProcess:(pid_t)processID
{
    return [self.BSDProcessList statusForProcessID:processID];
}

-(void) updateStatusForProcess:(pid_t)processID
{
    // TODO: temp kludge
    [self updateProcessIDs];
}

#pragma mark NSTableViewDataSource

-(NSInteger) numberOfRowsInTableView:(NSTableView*)tableView
{
    return [self.processIDs count];
}

-(id) tableView:(NSTableView*)aTableView objectValueForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
    if ([[aTableColumn identifier] isEqualToString:@"name"])
    {
        return [self nameForProcess:[[self.processIDs objectAtIndex:rowIndex] intValue]];
    }
    else if ([[aTableColumn identifier] isEqualToString:@"pid"])
    {
        return [self.processIDs objectAtIndex:rowIndex];
    }
    else if ([[aTableColumn identifier] isEqualToString:@"cpu"])
    {
        return @([self CPUTimeForProcess:[[self.processIDs objectAtIndex:rowIndex] intValue]]);
    }
    else if ([[aTableColumn identifier] isEqualToString:@"energy"])
    {
        return @([self energyForProcess:[[self.processIDs objectAtIndex:rowIndex] intValue]]);
    }
    else if ([[aTableColumn identifier] isEqualToString:@"status"])
    {
        return [self statusForProcess:[[self.processIDs objectAtIndex:rowIndex] intValue]];
    }

    return nil;
}

- (void)tableView:(NSTableView*)tableView sortDescriptorsDidChange:(NSArray*)oldDescriptors
{
    if (tableView != nil)
    {
        self.cachedSortDescriptors = [tableView sortDescriptors];
    }
    
    [self updateProcessIDs];
}

#pragma mark - Sorting and Filtering

-(void) setFilter:(NSString*)filter
{
    _filter = filter;
    
    [self updateProcessIDs];
}

-(void) setShowOnlyHighUsage:(BOOL)showOnlyHighUsage
{
    _showOnlyHighUsage = showOnlyHighUsage;
    
    [self updateProcessIDs];
}

-(NSArray*) sort:(NSArray*)processIDs withSortDescriptors:(NSArray*)sortDescriptors
{
    NSMutableArray* array = [NSMutableArray arrayWithArray:processIDs];
    [array sortUsingComparator:^NSComparisonResult(id obj1, id obj2)
     {
         NSComparisonResult result = NSOrderedSame;
         
         for (NSSortDescriptor* descriptor in sortDescriptors)
         {
             result = [self compareProcessID1:[obj1 intValue] processID2:[obj2 intValue] byKey:[descriptor key]];
             
             if (result != NSOrderedSame)
             {
                 result *= ([descriptor ascending] ? 1 : -1);
                 break;
             }
         }
         
         return result;
     }];
    
    return array;
}

// TODO: this should probably use an NSPredicate, but whatever
-(NSArray*) filter:(NSArray*)processIDs withFilter:(NSString*)filter
{
    if (!self.showOnlyHighUsage && [filter length] == 0)
    {
        return processIDs;
    }
    
    NSMutableArray* newArray = [NSMutableArray array];
    filter = [filter uppercaseString];
    
    for (NSNumber* processID in processIDs)
    {
        pid_t processIDNum = [processID intValue];
        if (self.showOnlyHighUsage)
        {
            if ([self energyForProcess:processIDNum] < 0.01f)
            {
                continue;
            }
            else
            {
                if ([filter length] == 0)
                {
                    [newArray addObject:processID];
                    continue;
                }
            }
        }
        
        NSString* appName = [[self nameForProcess:[processID intValue]] uppercaseString];
        NSUInteger filterIndex = 0;
        
        for (NSUInteger i = 0; i < [appName length]; i++)
        {
            char filterChar = [filter characterAtIndex:filterIndex];
            char appChar = [appName characterAtIndex:i];
            
            if (filterChar == appChar)
            {
                filterIndex++;
                
                if (filterIndex == [filter length])
                {
                    [newArray addObject:processID];
                    break;
                }
            }
        }
    }
    
    return newArray;
}

-(NSComparisonResult) compareProcessID1:(pid_t)processID1 processID2:(pid_t)processID2 byKey:(NSString*)key
{
    if ([key isEqualToString:@"name"])
    {
         return [[[self nameForProcess:processID1] uppercaseString] compare:[[self nameForProcess:processID2] uppercaseString]];
    }
    else if ([key isEqualToString:@"pid"])
    {
         return [@(processID1) compare:@(processID2)];
    }
    else if ([key isEqualToString:@"status"])
    {
        NSString* status1 = [self statusForProcess:processID1];
        NSString* status2 = [self statusForProcess:processID2];
        return [status1 compare:status2];
    }
    else
    {
        return 0;
    }
}

@end
