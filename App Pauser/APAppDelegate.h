//
//  APAppDelegate.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

// features:
// TODO: sorting by energy & CPU
// TODO: adjust energy whenever apps are added, closed, or paused
// TODO: query
// TODO: resizing behavior
// TODO: filter high energy use
// TODO: real-time updating of filter, sort, etc.

// optimizations:
// TODO: very slow filtering and sorting
// TODO: only update CPU/energy for needed cells
// TODO: don't query in background

// bug fixes:
// TODO: gather all NSTasks to cancel if quit
// TODO: make sure quitting works as intended
// TODO: gray area on bottom of scroll instead of empty rows
// TODO: tapping quickly repeatedly on button crashes

// TODO: correct CALayer behavior for maximally smooth scrolling
// TODO: taskbar drop-down icon
// TODO: remember size & filter

#import <Cocoa/Cocoa.h>
#import "APProcessDataSource.h"

@interface NSLayerBackedClipView : NSClipView
@end

@interface APAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDelegate, NSTextFieldDelegate>

@property (assign) IBOutlet NSWindow* window;
@property (assign) IBOutlet NSTableView* table;
@property (assign) IBOutlet NSButton* button;
@property (assign) IBOutlet NSSearchField* searchField;

@property (nonatomic, retain) APProcessDataSource* dataSource;

-(IBAction) buttonPushed:(NSButton*)sender;
-(IBAction) togglePushed:(NSButton*)sender;

-(void) updateButtonLabelWithRow:(NSInteger)rowIndex;

@end
