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

@property (nonatomic, retain) NSMutableDictionary* cachedProcessIDsToStatuses;
@property (nonatomic, retain) NSMutableDictionary* currentProcessIDsToCPU;
@property (nonatomic, retain) NSMutableDictionary* processIDsToEnergy;

@property (nonatomic, assign, readwrite) NSInteger cpuTimeUpdateTick;
@property (nonatomic, retain) NSTask* topTask;
@property (nonatomic, retain) NSArray* cachedSortDescriptors;
@property (nonatomic, retain) NSRegularExpression* topTaskRegex;
@property (nonatomic, retain) NSRegularExpression* psRegex;
@property (nonatomic, retain) NSRegularExpression* psCPURegex;
@property (nonatomic, retain) NSTimer* CPUUpdateTimer;
@property (nonatomic, assign) CGFloat totalEnergy;

-(void) updateProcessIDs;

@end

@implementation APProcessDataSource

-(void) dealloc
{
    [[NSWorkspace sharedWorkspace] removeObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications))];
    [self.topTask interrupt];
    [self.CPUUpdateTimer invalidate];
}

-(id) init
{
    self = [super init];
    if (self)
    {
        self.processIDs = [NSArray array];
        self.processIDsToEnergy = [NSMutableDictionary dictionary];

        self.topTaskRegex = [NSRegularExpression regularExpressionWithPattern:@"\\s*(\\d+)\\s+(\\d+\\.\\d+)\\s*"
                                                                      options:0
                                                                        error:NULL];
        self.psRegex = [NSRegularExpression regularExpressionWithPattern:@"\\n[^\\n]*?\\s*(\\d+)\\s+([a-zA-Z]+)\\s*\\n"
                                                                               options:0
                                                                                 error:NULL];
        self.psCPURegex = [NSRegularExpression regularExpressionWithPattern:@"\\n[^\\n]*?\\s*(\\d+)\\s+(\\d+.\\d+)\\s*\\n"
                                                                    options:0
                                                                      error:NULL];
        
//        self.CPUUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(pollCPUAsync) userInfo:nil repeats:YES];
        self.BSDProcessList = [[APBSDProcessList alloc] init];
        
        [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications)) options:NSKeyValueObservingOptionInitial context:NULL];
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
    [self.BSDProcessList refreshProcessList];
    NSMutableArray* processIDs = [NSMutableArray arrayWithArray:[self.BSDProcessList processIDs]];
    
    self.processIDsToApplications = [NSMutableDictionary dictionary];
    
    for (NSRunningApplication* application in runningApplications)
    {
        [processIDs addObject:@([application processIdentifier])];
        self.processIDsToApplications[@([application processIdentifier])] = application;
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

//-(void) pollAllProcesses
//{
//    double startTime = CACurrentMediaTime();
//    
//    [self.BSDProcessList refreshProcessList];
//    [self.BSDProcessList refreshProcessList];
//    [self.BSDProcessList refreshProcessList];
//    [self.BSDProcessList refreshProcessList];
//    
//    for (NSNumber* number in [self.BSDProcessList processIDs])
//    {
//        int asdf = 123;
//        asdf = asdf;
//    }
//    
//    double endTime = CACurrentMediaTime();
//    
//    NSLog(@"Time: %lf", endTime-startTime);
//}

//-(void) pollCPU
//{
//    self.currentProcessIDsToCPU = [NSMutableDictionary dictionary];
//    
//    for (NSRunningApplication* application in self.runningApplications)
//    {
//        NSString* pidKey = [NSString stringWithFormat:@"%d", [application processIdentifier]];
//        self.currentProcessIDsToCPU[pidKey] = @"0.0";
//    }
//    
//    // launch ps task
//    NSTask* statusTask = [[NSTask alloc] init];
//    [statusTask setLaunchPath:@"/bin/ps"];
//    NSArray* arguments = arguments = [NSArray arrayWithObjects:@"aux", @"-o", @"pid,%cpu", nil];
//    [statusTask setArguments:arguments];
//    statusTask.standardOutput = [NSPipe pipe];
//    [statusTask launch];
//    [statusTask waitUntilExit];
//    
//    // make sure exit status is OK
//    int terminationStatus = [statusTask terminationStatus];
//    NSAssert(terminationStatus == 0, @"ps returned with a termination status of %d", terminationStatus);
//    
//    // capture output data from pipe
//    NSData* outputData = [[statusTask.standardOutput fileHandleForReading] readDataToEndOfFile];
//    NSString* outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
//    CGFloat totalMeasuredLoad = 0;
//    
//    // process output data
//    NSArray* matches = [self.psCPURegex matchesInString:outputString options:0 range:NSMakeRange(0, [outputString length])];
//    for (NSTextCheckingResult* match in matches)
//    {
//        NSString* processID = [outputString substringWithRange:[match rangeAtIndex:1]];
//        NSString* cpu = [outputString substringWithRange:[match rangeAtIndex:2]];
//        
//        if (self.currentProcessIDsToCPU[processID])
//        {
//            CGFloat cpuValue = [cpu doubleValue];
//            
//            self.currentProcessIDsToCPU[processID] = cpu;
//            
//            if (self.processIDsToEnergy[processID])
//            {
//                self.processIDsToEnergy[processID] = @([self.processIDsToEnergy[processID] doubleValue] + cpuValue);
//            }
//            else
//            {
//                self.processIDsToEnergy[processID] = @0;
//            }
//            
//            totalMeasuredLoad += cpuValue;
//        }
//    }
//    
//    self.totalEnergy += 100;
//    self.cpuTimeUpdateTick++;
//}

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
    // TODO:
    return 0;
}

-(CGFloat) energyForProcess:(pid_t)processID
{
    // TODO:
    return 0;
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
    // TODO: what is this even for?
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
    if ([filter length] == 0)
    {
        return processIDs;
    }
    
    NSMutableArray* newArray = [NSMutableArray array];
    filter = [filter uppercaseString];
    
    for (NSNumber* processID in processIDs)
    {
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
         return [[self nameForProcess:processID1] compare:[self nameForProcess:processID2]];
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
