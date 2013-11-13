//
//  APProcessDataSource.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/12/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APProcessDataSource.h"

@interface APProcessDataSource ()

@property (nonatomic, retain) NSArray* runningApplications;
@property (nonatomic, retain, readwrite) NSArray* applications;
@property (nonatomic, retain) NSMutableDictionary* processIDToCPUTime;
@property (nonatomic, retain) NSTask* topTask;
@property (nonatomic, retain) NSMutableDictionary* cachedProcessIDsToStatuses;
@property (nonatomic, retain) NSArray* cachedSortDescriptors;
@property (nonatomic, retain) NSRegularExpression* topTaskRegex;
@property (nonatomic, retain) NSRegularExpression* psRegex;

@end

@implementation APProcessDataSource

-(void) dealloc
{
    [[NSWorkspace sharedWorkspace] removeObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications))];
    [self.topTask interrupt];
}

-(id) init
{
    self = [super init];
    if (self)
    {
        self.runningApplications = [NSArray array];
        self.applications = [NSArray array];
        self.processIDToCPUTime = [NSMutableDictionary dictionary];

        self.topTaskRegex = [NSRegularExpression regularExpressionWithPattern:@"\\s*(\\d+)\\s+(\\d+\\.\\d+)\\s*"
                                                                      options:0
                                                                        error:NULL];
        self.psRegex = [NSRegularExpression regularExpressionWithPattern:@"\\n[^\\n]*?\\s*(\\d+)\\s+([a-zA-Z]+)\\s*\\n"
                                                                               options:0
                                                                                 error:NULL];
        
//
//        self.topTask = [[NSTask alloc] init];
//        [self.topTask setLaunchPath:@"/usr/bin/top"];
//        //    NSArray* arguments = [NSArray arrayWithObjects: @"-s", @"1",@"-l",@"3600",@"-stats",@"pid,cpu", nil];
//        NSArray* arguments = [NSArray arrayWithObjects:@"-l", @"3600", @"-stats", @"pid,cpu", nil];
//        [self.topTask setArguments:arguments];
//        
//        NSPipe* standardOutputPipe = [NSPipe pipe];
//        self.topTask.standardOutput = standardOutputPipe;
//        //    [self.topTask launch];
//        
//        [[self.topTask.standardOutput fileHandleForReading] setReadabilityHandler:^(NSFileHandle* file)
//         {
//             NSData* topData = [file availableData];
//             NSString* topString = [[NSString alloc] initWithData:topData encoding:NSUTF8StringEncoding];
//             NSArray* matches = [self.topTaskRegex matchesInString:topString options:0 range:NSMakeRange(0, [topString length])];
//             
//             for (NSTextCheckingResult* match in matches)
//             {
//                 NSString* processID = [topString substringWithRange:[match rangeAtIndex:1]];
//                 NSString* CPUTime = [topString substringWithRange:[match rangeAtIndex:2]];
//                 
//                 if (self.processIDToCPUTime[processID])
//                 {
//                     self.processIDToCPUTime[processID] = CPUTime;
//                 }
//             }
//             
//             //        [self.table reloadData];
//         }];
        
        [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:NSStringFromSelector(@selector(runningApplications)) options:NSKeyValueObservingOptionInitial context:NULL];
    }
    return self;
}

-(void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    if (object == [NSWorkspace sharedWorkspace] && [keyPath isEqualToString:NSStringFromSelector(@selector(runningApplications))])
    {
        [self updateRunningApplications];
    }
}

-(void) updateRunningApplications
{
    // why do it like this? so that any KVO observers don't get two messages
    self.runningApplications = [NSArray arrayWithArray:[[NSWorkspace sharedWorkspace] runningApplications]];
    NSArray* filteredApplications = [self filter:self.runningApplications];
    NSArray* sortedApplications = [self sort:filteredApplications WithSortDescriptors:self.cachedSortDescriptors];
    self.applications = sortedApplications;
    
    for (NSRunningApplication* runningApplication in self.runningApplications)
    {
        self.processIDToCPUTime[@([runningApplication processIdentifier])] = @"0.0";
    }
}

-(BOOL) suspend:(BOOL)suspend application:(NSRunningApplication*)application
{
    NSString* processIDString = [NSString stringWithFormat:@"%d", [application processIdentifier]];
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
    
    [self updateStatusForApplication:application];
    
    if (suspend == [self applicationIsSuspended:application])
    {
        return YES;
    }
    else
    {
        NSAssert(NO, @"application could not suspend");
        return NO;
    }
}

-(BOOL) applicationIsSuspended:(NSRunningApplication*)application
{
    return ([[[self applicationStatus:application] substringToIndex:1] isEqualToString:@"T"]);
}

-(NSString*) applicationStatus:(NSRunningApplication*)application
{
    NSAssert(application != nil, @"can't pass nil application to applicationStatus");
    
    NSString* pidKey = [NSString stringWithFormat:@"%d", [application processIdentifier]];

    if (!self.cachedProcessIDsToStatuses[pidKey])
    {
        // attempt to retrieve manually
        [self updateStatusForApplication:application];
        
        NSAssert(self.cachedProcessIDsToStatuses[pidKey], @"ps could not find process %@", pidKey);
        
        if (!self.cachedProcessIDsToStatuses[pidKey])
        {
            return @"   ";
        }
        else
        {
            return self.cachedProcessIDsToStatuses[pidKey];
        }
    }
    else
    {
        return self.cachedProcessIDsToStatuses[pidKey];
    }
}

-(void) updateStatusForApplication:(NSRunningApplication*)application
{
    BOOL refreshAll = (application == nil);
    NSString* pidKey = [NSString stringWithFormat:@"%d", [application processIdentifier]];
    
    // create cache
    if (!self.cachedProcessIDsToStatuses || refreshAll)
    {
        self.cachedProcessIDsToStatuses = [NSMutableDictionary dictionary];
    }
    
    // ensure that we're not trying to ps a dead process
    if (!refreshAll)
    {
        if ([application isTerminated])
        {
            if (self.cachedProcessIDsToStatuses[pidKey])
            {
                [self.cachedProcessIDsToStatuses removeObjectForKey:pidKey];
                return;
            }
        }
    }
    
    // launch ps task
    NSTask* statusTask = [[NSTask alloc] init];
    [statusTask setLaunchPath:@"/bin/ps"];
    NSArray* arguments;
    if (refreshAll)
    {
        arguments = [NSArray arrayWithObjects:@"aux", @"-o", @"pid,state", nil];
    }
    else
    {
        arguments = [NSArray arrayWithObjects:@"-p", [NSString stringWithFormat:@"%d", [application processIdentifier]], @"-o", @"pid,state", nil];
    }
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
    
    // process output data
    NSArray* matches = [self.psRegex matchesInString:outputString options:0 range:NSMakeRange(0, [outputString length])];
    for (NSTextCheckingResult* match in matches)
    {
        NSString* processID = [outputString substringWithRange:[match rangeAtIndex:1]];
        NSString* status = [outputString substringWithRange:[match rangeAtIndex:2]];
        
        self.cachedProcessIDsToStatuses[processID] = status;
    }
}

-(CGFloat) getCPUTimeForProcess:(pid_t)process
{
    //    NSLog(@"%d is running? %d", process, [task isRunning]);
    return 0.5f;
}

#pragma mark NSTableViewDataSource

-(NSInteger) numberOfRowsInTableView:(NSTableView*)tableView
{
    return [self.runningApplications count];
}

- (void)tableView:(NSTableView*)tableView sortDescriptorsDidChange:(NSArray*)oldDescriptors
{
    if (tableView != nil)
    {
        self.cachedSortDescriptors = [tableView sortDescriptors];
    }
    
    [self updateRunningApplications];
}

#pragma mark - Sorting and Filtering

-(NSArray*) sort:(NSArray*)applications WithSortDescriptors:(NSArray*)sortDescriptors
{
    NSMutableArray* array = [NSMutableArray arrayWithArray:applications];
    [array sortUsingComparator:^NSComparisonResult(id obj1, id obj2)
     {
         NSComparisonResult result = NSOrderedSame;
         
         for (NSSortDescriptor* descriptor in sortDescriptors)
         {
             result = [self compareApplication1:obj1 application2:obj2 byKey:[descriptor key]];
             
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

-(NSArray*) filter:(NSArray*)applications
{
    return applications;
}

-(NSComparisonResult) compareApplication1:(NSRunningApplication*)app1 application2:(NSRunningApplication*)app2 byKey:(NSString*)key
{
    if ([key isEqualToString:@"name"])
    {
         return [[app1 localizedName] compare:[app2 localizedName]];
    }
    else if ([key isEqualToString:@"pid"])
    {
         return [@([app1 processIdentifier]) compare:@([app2 processIdentifier])];
    }
    else if ([key isEqualToString:@"status"])
    {
        NSString* status1 = [self applicationStatus:app1];
        NSString* status2 = [self applicationStatus:app2];
        return [status1 compare:status2];
    }
    else
    {
        return 0;
    }
}

@end
