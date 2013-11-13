//
//  APAppDelegate.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

// TODO: search filter
// TODO: sorting
// TODO: gather all NSTasks to cancel if quit
// TODO: make sure quitting works as intended
// TODO: laggy scrolling -- Activity Monitor doesn't lag
// TODO: more accurate energy, in terms of maximum possible spending
// TODO: adjust energy whenever apps are added, closed, or paused

#import <Cocoa/Cocoa.h>
#import "APProcessDataSource.h"

@interface APAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDelegate, NSTextDelegate>

@property (assign) IBOutlet NSWindow* window;
@property (assign) IBOutlet NSTableView* table;
@property (assign) IBOutlet NSButton* button;
@property (assign) IBOutlet NSSearchField* searchField;

@property (nonatomic, retain) APProcessDataSource* dataSource;

-(IBAction) buttonPushed:(id)sender;
-(void) updateButtonLabelWithRow:(NSInteger)rowIndex;

@end
