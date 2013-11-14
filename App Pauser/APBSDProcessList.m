//
//  GetBSDProcessList.cpp
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/13/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#include "APBSDProcessList.h"

// from https://developer.apple.com/legacy/library/qa/qa2001/qa1123.html

#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/sysctl.h>

int GetBSDProcessList(kinfo_proc **procList, size_t *procCount)
// Returns a list of all BSD processes on the system.  This routine
// allocates the list and puts it in *procList and a count of the
// number of entries in *procCount.  You are responsible for freeing
// this list (use "free" from System framework).
// On success, the function returns 0.
// On error, the function returns a BSD errno value.
{
    int                 err;
    kinfo_proc *        result;
    bool                done;
    static const int    name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    // Declaring name as const requires us to cast it when passing it to
    // sysctl because the prototype doesn't include the const modifier.
    size_t              length;
    
    assert( procList != NULL);
    assert(*procList == NULL);
    assert(procCount != NULL);
    
    *procCount = 0;
    
    // We start by calling sysctl with result == NULL and length == 0.
    // That will succeed, and set length to the appropriate length.
    // We then allocate a buffer of that size and call sysctl again
    // with that buffer.  If that succeeds, we're done.  If that fails
    // with ENOMEM, we have to throw away our buffer and loop.  Note
    // that the loop causes use to call sysctl with NULL again; this
    // is necessary because the ENOMEM failure case sets length to
    // the amount of data returned, not the amount of data that
    // could have been returned.
    
    result = NULL;
    done = false;
    do {
        assert(result == NULL);
        
        // Call sysctl with a NULL buffer.
        
        length = 0;
        err = sysctl( (int *) name, (sizeof(name) / sizeof(*name)) - 1,
                     NULL, &length,
                     NULL, 0);
        if (err == -1) {
            err = errno;
        }
        
        // Allocate an appropriately sized buffer based on the results
        // from the previous call.
        
        if (err == 0) {
            result = malloc(length);
            if (result == NULL) {
                err = ENOMEM;
            }
        }
        
        // Call sysctl again with the new buffer.  If we get an ENOMEM
        // error, toss away our buffer and start again.
        
        if (err == 0) {
            err = sysctl( (int *) name, (sizeof(name) / sizeof(*name)) - 1,
                         result, &length,
                         NULL, 0);
            if (err == -1) {
                err = errno;
            }
            if (err == 0) {
                done = true;
            } else if (err == ENOMEM) {
                assert(result != NULL);
                free(result);
                result = NULL;
                err = 0;
            }
        }
    } while (err == 0 && ! done);
    
    // Clean up and establish post conditions.
    
    if (err != 0 && result != NULL) {
        free(result);
        result = NULL;
    }
    *procList = result;
    if (err == 0) {
        *procCount = length / sizeof(kinfo_proc);
    }
    
    assert( (err == 0) == (*procList != NULL) );
    
    return err;
}

@interface APBSDProcessList ()
@property (nonatomic, retain) NSDictionary* processIDToInfoStruct;
@end

@implementation APBSDProcessList

-(void) dealloc
{
    if (procList)
    {
        free(procList);
    }
}

-(id) init
{
    self = [super init];
    if (self)
    {
        procList = NULL;
    }
    return self;
}

-(void) refreshProcessList
{
    if (procList)
    {
        free(procList);
    }
    procList = NULL;
    
    GetBSDProcessList(&procList, &procCount);
    
    NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
    for (int i = 0; i < procCount; i++)
    {
        [dictionary setObject:[NSValue valueWithBytes:&procList[i] objCType:@encode(kinfo_proc)]
                       forKey:@(procList[i].kp_proc.p_pid)];
    }
    
    self.processIDToInfoStruct = dictionary;
}

-(NSArray*) processIDs
{
    return [self.processIDToInfoStruct allKeys];
}

-(NSString*) nameForProcessID:(pid_t)processID
{
    if (self.processIDToInfoStruct[@(processID)])
    {
        kinfo_proc info;
        [self.processIDToInfoStruct[@(processID)] getValue:&info];
        return [NSString stringWithCString:info.kp_proc.p_comm encoding:NSUTF8StringEncoding];
    }
    else
    {
        return nil;
    }
}

-(NSString*) statusForProcessID:(pid_t)processID
{
    if (self.processIDToInfoStruct[@(processID)])
    {
        kinfo_proc info;
        [self.processIDToInfoStruct[@(processID)] getValue:&info];
        
        switch (info.kp_proc.p_stat)
        {
            case SIDL:
                return @"I";
                break;
            case SRUN:
                return @"R";
                break;
            case SSLEEP:
                return @"S";
                break;
            case SSTOP:
                return @"T";
                break;
            case SZOMB:
                return @"Z";
                break;
            default:
                return nil;
                break;
        }
    }
    else
    {
        return nil;
    }
}

@end
