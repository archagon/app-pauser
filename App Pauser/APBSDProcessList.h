//
//  GetBSDProcessList.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/13/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct kinfo_proc kinfo_proc;

@interface APBSDProcessList : NSObject
{
    @protected
    kinfo_proc* procList;
    size_t procCount;
}

-(void) refreshProcessList;
-(NSArray*) processIDs;
-(NSString*) nameForProcessID:(pid_t)processID;
-(NSString*) statusForProcessID:(pid_t)processID;

@end
