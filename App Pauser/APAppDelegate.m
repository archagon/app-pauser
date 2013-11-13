//
//  APAppDelegate.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APAppDelegate.h"

// TODO: notifications, etc.

@implementation APAppDelegate

-(void) dealloc
{
    [self.dataSource removeObserver:self forKeyPath:NSStringFromSelector(@selector(applications))];
}

-(void) applicationDidFinishLaunching:(NSNotification*)aNotification
{
    self.searchField.currentEditor.delegate = self;
    
    self.dataSource = [[APProcessDataSource alloc] init];
    [self.dataSource addObserver:self forKeyPath:NSStringFromSelector(@selector(applications)) options:0 context:NULL];
    [self.dataSource updateStatusForApplication:nil];
    self.table.dataSource = self.dataSource;
    
    for (NSTableColumn* column in [self.table tableColumns])
    {
        NSString* columnID = [column identifier];
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:columnID ascending:YES];
        [column setSortDescriptorPrototype:sortDescriptor];
        
        if ([[self.table sortDescriptors] count] == 0)
        {
            [self.table setSortDescriptors:[NSArray arrayWithObject:[column sortDescriptorPrototype]]];
        }
    }
}

-(void) applicationWillTerminate:(NSNotification*)notification
{
}

-(void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    if (object == self.dataSource && [keyPath isEqualToString:NSStringFromSelector(@selector(applications))])
    {
        [self.table reloadData];
    }
}

-(IBAction) buttonPushed:(id)sender
{
    // TODO: save tasks
    // TODO: can't stop current process
    
    NSInteger selectedRowIndex = [self.table selectedRow];
    NSRunningApplication* application = self.dataSource.applications[selectedRowIndex];
    
    if (![application isTerminated])
    {
        BOOL isSuspended = [self.dataSource applicationIsSuspended:application];
        
        BOOL suspendSucceeded = [self.dataSource suspend:!isSuspended application:application];
        
        NSIndexSet* currentRow = [[NSIndexSet alloc] initWithIndex:selectedRowIndex];
        NSIndexSet* allColumns = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, [self.table numberOfColumns])];
        [self.table reloadDataForRowIndexes:currentRow columnIndexes:allColumns];
        
        [self updateButtonLabelWithRow:selectedRowIndex];
    }
    else
    {
        NSAssert(NO, @"attempting to pause application that is no longer running");
    }
}

-(BOOL) tableView:(NSTableView*)tableView shouldSelectRow:(NSInteger)row
{
    [self updateButtonLabelWithRow:row];
    return YES;
}

-(void) updateButtonLabelWithRow:(NSInteger)rowIndex
{
    if (rowIndex == -1)
    {
        return;
    }
    
    NSRunningApplication* application = self.dataSource.applications[rowIndex];
    
    if ([application isEqual:[NSRunningApplication currentApplication]])
    {
        [self.button setEnabled:NO];
        self.button.title = [NSString stringWithFormat:@"Can't pause myself!"];
        return;
    }
    else
    {
        [self.button setEnabled:YES];
    }
    
    [self.dataSource updateStatusForApplication:application];
    
    if ([self.dataSource applicationIsSuspended:application])
    {
        self.button.title = [NSString stringWithFormat:@"Resume %@", [application localizedName]];
    }
    else
    {
        self.button.title = [NSString stringWithFormat:@"Pause %@", [application localizedName]];
    }
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    if ([self.dataSource.applications count] == 0)
    {
        return nil;
    }
    
    NSRunningApplication* currentApplication = self.dataSource.applications[row];
    BOOL applicationIsSuspended = [self.dataSource applicationIsSuspended:currentApplication];
    NSString* status = [self.dataSource applicationStatus:currentApplication];
    
    NSTableCellView* cellView = [tableView makeViewWithIdentifier:[tableColumn identifier] owner:self];
    
    if ([[tableColumn identifier] isEqualToString:@"name"])
    {
        cellView.textField.stringValue = [currentApplication localizedName];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.imageView.image = [currentApplication icon];
        cellView.imageView.alphaValue = (applicationIsSuspended ? 0.5f : 1.0f);
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    else if ([[tableColumn identifier] isEqualToString:@"pid"])
    {
        cellView.textField.stringValue = [NSString stringWithFormat:@"%d", [currentApplication processIdentifier]];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    else if ([[tableColumn identifier] isEqualToString:@"cpu"])
    {
        cellView.textField.stringValue = @"";
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    else if ([[tableColumn identifier] isEqualToString:@"energy"])
    {
//        if (self.processIDToCPUTime[@([currentApplication processIdentifier])])
//        {
//            cellView.textField.stringValue = self.processIDToCPUTime[@([currentApplication processIdentifier])];
//        }
//        else
//        {
            cellView.textField.stringValue = @"";
//        }
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    else if ([[tableColumn identifier] isEqualToString:@"status"])
    {
        //https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/ps.1.html
        //I       Marks a process that is idle (sleeping for longer than about 20 seconds).
        //R       Marks a runnable process.
        //S       Marks a process that is sleeping for less than about 20 seconds.
        //T       Marks a stopped process.
        //U       Marks a process in uninterruptible wait.
        //Z       Marks a dead process (a ``zombie'').
    
        if ([[status substringToIndex:1] isEqualToString:@"I"] ||
            [[status substringToIndex:1] isEqualToString:@"S"] ||
            [[status substringToIndex:1] isEqualToString:@"U"])
        {
            status = [@"❎ " stringByAppendingString:status];
        }
        else if ([[status substringToIndex:1] isEqualToString:@"R"])
        {
            status = [@"▶️ " stringByAppendingString:status];
        }
        else if ([[status substringToIndex:1] isEqualToString:@"T"])
        {
            status = [@"💤 " stringByAppendingString:status];
        }
        else if ([[status substringToIndex:1] isEqualToString:@"Z"])
        {
            status = [@"🆘 " stringByAppendingString:status];
        }
        else
        {
            status = [@"⁉️ " stringByAppendingString:status];
        }
        
        [cellView.imageView setHidden:YES];
        cellView.textField.stringValue = status;
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    
    return cellView;
}

-(void) textDidChange:(NSNotification*)notification
{
    self.dataSource.filter = self.searchField.currentEditor.string;
}

@end
