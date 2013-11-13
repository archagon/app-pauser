//
//  APAppDelegate.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

// TODO: search filter
// TODO: sorting
// TODO: actually check if paused, especially on launch!
// TODO: gather all NSTasks to cancel if quit
// TODO: make sure quitting works as intended

#import <Cocoa/Cocoa.h>
#import "APProcessDataSource.h"

@interface APAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDelegate>

@property (assign) IBOutlet NSWindow* window;
@property (assign) IBOutlet NSTableView* table;
@property (assign) IBOutlet NSButton* button;
@property (nonatomic, retain) APProcessDataSource* dataSource;

-(IBAction) buttonPushed:(id)sender;
-(void) updateButtonLabelWithRow:(NSInteger)rowIndex;

@end