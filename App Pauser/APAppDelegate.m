//
//  APAppDelegate.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APAppDelegate.h"

@implementation NSLayerBackedClipView

- (CALayer*) makeBackingLayer
{
    return [CAScrollLayer layer];
}

@end

@implementation APAppDelegate

// TODO: notifications, etc.
-(void) dealloc
{
    [self.dataSource removeObserver:self forKeyPath:NSStringFromSelector(@selector(applications))];
    [self.dataSource removeObserver:self forKeyPath:NSStringFromSelector(@selector(cpuTimeUpdateTick))];
}

-(void) applicationDidFinishLaunching:(NSNotification*)aNotification
{
    self.searchField.currentEditor.delegate = self;
    
    self.dataSource = [[APProcessDataSource alloc] init];
    [self.dataSource addObserver:self forKeyPath:NSStringFromSelector(@selector(applications)) options:0 context:NULL];
    [self.dataSource addObserver:self forKeyPath:NSStringFromSelector(@selector(cpuTimeUpdateTick)) options:NSKeyValueObservingOptionInitial context:NULL];
    [self.dataSource updateStatusForApplication:nil];
    self.table.dataSource = self.dataSource;
    
    // TODO: I still don't really know how all this stuff works, especially with implicit child layers
    //[[[self.table superview] layer] setOpaque:YES];
    //[[[self.table superview] layer] setDrawsAsynchronously:YES];
    //[[self.table superview] setLayerContentsRedrawPolicy:NSViewLayerContentsRedrawOnSetNeedsDisplay];
    
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
    
    [self.table setAllowsTypeSelect:NO]; // TODO: too slow with button label changes, figure out later
}

-(void) applicationWillTerminate:(NSNotification*)notification
{
}

-(void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    if (object == self.dataSource)
    {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(applications))])
        {
            [self.table reloadData];
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(cpuTimeUpdateTick))])
        {
            NSIndexSet* allRows = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, [self.table numberOfRows])];
            NSMutableIndexSet* cpuColumn = [NSMutableIndexSet indexSet];
            [cpuColumn addIndex:[self.table columnWithIdentifier:@"cpu"]];
            [cpuColumn addIndex:[self.table columnWithIdentifier:@"energy"]];
            [self.table reloadDataForRowIndexes:allRows columnIndexes:cpuColumn];
        }
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
        cellView.textField.stringValue = [self.dataSource CPUTimeForApplication:currentApplication];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
    }
    else if ([[tableColumn identifier] isEqualToString:@"energy"])
    {
        CGFloat energy = [self.dataSource energyForApplication:currentApplication];
        
        cellView.textField.stringValue = [NSString stringWithFormat:@"%.1f", energy * 100];
        cellView.backgroundStyle = (applicationIsSuspended ? NSBackgroundStyleDark : NSBackgroundStyleLight);
        
        if (energy < [[APSettings settingForKeyPath:@"energythreshholds.medium"] doubleValue])
        {
            cellView.textField.textColor = [NSColor blackColor];
        }
        else if (energy < [[APSettings settingForKeyPath:@"energythreshholds.high"] doubleValue])
        {
            cellView.textField.textColor = [NSColor orangeColor];
        }
        else
        {
            cellView.textField.textColor = [NSColor redColor];
        }
    }
    else if ([[tableColumn identifier] isEqualToString:@"status"])
    {
        status = [APSettings settingForKeyPath:[@"statussymbols." stringByAppendingString:[status substringToIndex:1]]];
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
