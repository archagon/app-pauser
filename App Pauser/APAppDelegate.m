//
//  APAppDelegate.m
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/11/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#import "APAppDelegate.h"
#import <Quartz/Quartz.h>

@implementation NSLayerBackedClipView

- (CALayer*) makeBackingLayer
{
    return [CAScrollLayer layer];
}

@end

@interface APAppDelegate ()

@property (nonatomic, retain) NSColor* cachedRowColor1;
@property (nonatomic, retain) NSColor* cachedRowColor2;

@end

@implementation APAppDelegate

// TODO: notifications, etc.
-(void) dealloc
{
    [self.dataSource removeObserver:self forKeyPath:NSStringFromSelector(@selector(processIDs))];
    [self.dataSource removeObserver:self forKeyPath:NSStringFromSelector(@selector(cpuTimeUpdateTick))];
}

-(void) applicationDidFinishLaunching:(NSNotification*)aNotification
{
    self.searchField.delegate = self;
    
    self.dataSource = [[APProcessDataSource alloc] init];
    [self.dataSource addObserver:self forKeyPath:NSStringFromSelector(@selector(processIDs)) options:0 context:NULL];
    [self.dataSource addObserver:self forKeyPath:NSStringFromSelector(@selector(cpuTimeUpdateTick)) options:NSKeyValueObservingOptionInitial context:NULL];
    [self.dataSource updateStatusForProcess:-1];
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
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(processIDs))])
        {
            ABTIME_AVG_START(reloadData);
            [self.table reloadData];
            ABTIME_AVG_END(reloadData, 1, YES);
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(cpuTimeUpdateTick))])
        {
            NSMutableIndexSet* rowsToChange = [NSMutableIndexSet indexSet];
            
            for (NSUInteger i = 0; i < [self.table numberOfRows]; i++)
            {
                NSTableRowView* rowView = [self.table rowViewAtRow:i makeIfNecessary:NO];
                NSTableCellView* cellView = [rowView viewAtColumn:[self.table columnWithIdentifier:@"cpu"]];
                
                pid_t processID = [[[self.dataSource processIDs] objectAtIndex:i] intValue];
                CGFloat newCPUValue = [self.dataSource CPUTimeForProcess:processID];
                CGFloat oldCPUValue = ([cellView objectValue] ? [[cellView objectValue] doubleValue] : 0);
                
                if (newCPUValue != oldCPUValue)
                {
                    [rowsToChange addIndex:i];
                }
            }
            
            NSMutableIndexSet* cpuColumn = [NSMutableIndexSet indexSet];
            [cpuColumn addIndex:[self.table columnWithIdentifier:@"cpu"]];
            [cpuColumn addIndex:[self.table columnWithIdentifier:@"energy"]];
//            [self.table reloadDataForRowIndexes:rowsToChange columnIndexes:cpuColumn];
        }
    }
}

-(IBAction) buttonPushed:(NSButton*)sender
{
    // TODO: save tasks
    // TODO: can't stop current process
    
    NSInteger selectedRowIndex = [self.table selectedRow];
    pid_t processID = [self.dataSource.processIDs[selectedRowIndex] intValue];
    
    BOOL isSuspended = [self.dataSource processIsSuspended:processID];
    
    BOOL suspendSucceeded = [self.dataSource suspend:!isSuspended process:processID];
    
    NSIndexSet* currentRow = [[NSIndexSet alloc] initWithIndex:selectedRowIndex];
    NSIndexSet* allColumns = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, [self.table numberOfColumns])];
    [self.table reloadDataForRowIndexes:currentRow columnIndexes:allColumns];
    
    [self updateButtonLabelWithRow:selectedRowIndex];
}

-(IBAction) togglePushed:(NSButton*)sender
{
    self.dataSource.showOnlyHighUsage = [sender state];
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
    
    pid_t processID = [self.dataSource.processIDs[rowIndex] intValue];
    
    if (processID == [[NSRunningApplication currentApplication] processIdentifier])
    {
        [self.button setEnabled:NO];
        self.button.title = [NSString stringWithFormat:@"Can't pause myself!"];
        return;
    }
    else
    {
        [self.button setEnabled:YES];
    }
    
    [self.dataSource updateStatusForProcess:processID];
    
    if ([self.dataSource processIsSuspended:processID])
    {
        self.button.title = [NSString stringWithFormat:@"Resume %@", [self.dataSource nameForProcess:processID]];
    }
    else
    {
        self.button.title = [NSString stringWithFormat:@"Pause %@", [self.dataSource nameForProcess:processID]];
    }
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    if ([self.dataSource.processIDs count] == 0)
    {
        return nil;
    }
    
    ABTIME_AVG_START(tableCellReload);
    
    pid_t processID = [self.dataSource.processIDs[row] intValue];
    BOOL applicationIsSuspended = [self.dataSource processIsSuspended:processID];
    NSString* status = [self.dataSource statusForProcess:processID];
    
    NSTableCellView* cellView = [tableView makeViewWithIdentifier:[tableColumn identifier] owner:self];
    
    if ([[tableColumn identifier] isEqualToString:@"name"])
    {
        cellView.textField.stringValue = [self.dataSource nameForProcess:processID];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
        cellView.imageView.image = [self.dataSource imageForProcess:processID];
        cellView.imageView.alphaValue = (applicationIsSuspended ? 0.5f : 1.0f);
    }
    else if ([[tableColumn identifier] isEqualToString:@"pid"])
    {
        cellView.textField.stringValue = [NSString stringWithFormat:@"%d", processID];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
    }
    else if ([[tableColumn identifier] isEqualToString:@"cpu"])
    {
        cellView.textField.stringValue = [NSString stringWithFormat:@"%.1f", [self.dataSource CPUTimeForProcess:processID]];
        cellView.textField.textColor = (applicationIsSuspended ? [NSColor grayColor] : [NSColor blackColor]);
    }
    else if ([[tableColumn identifier] isEqualToString:@"energy"])
    {
        CGFloat energy = [self.dataSource energyForProcess:processID];
        
        cellView.textField.stringValue = [NSString stringWithFormat:@"%.1f", energy * 100];
        
        NSColor* rowBackgroundColor = [[tableView rowViewAtRow:row makeIfNecessary:NO] backgroundColor];
        
        if (!self.cachedRowColor1)
        {
            self.cachedRowColor1 = rowBackgroundColor;
        }
        else if (!self.cachedRowColor2 && ![rowBackgroundColor isEqualTo:self.cachedRowColor1])
        {
            self.cachedRowColor2 = rowBackgroundColor;
        }
        
        if (energy < [[APSettings settingForKeyPath:@"energythreshholds.medium"] doubleValue])
        {
            cellView.textField.textColor = [NSColor blackColor];
            NSInteger rowModulo = (row + 1) % 2;
            NSColor* rowColor = (rowModulo % 2 ? self.cachedRowColor1 : self.cachedRowColor2);
            
            if (![rowBackgroundColor isEqualTo:rowColor])
            {
                [[tableView rowViewAtRow:row makeIfNecessary:NO] setBackgroundColor:rowColor];
            }
        }
        else if (energy < [[APSettings settingForKeyPath:@"energythreshholds.high"] doubleValue])
        {
            cellView.textField.textColor = [NSColor orangeColor];
            [[tableView rowViewAtRow:row makeIfNecessary:NO] setBackgroundColor:[NSColor orangeColor]];
        }
        else
        {
            cellView.textField.textColor = [NSColor redColor];
            [[tableView rowViewAtRow:row makeIfNecessary:NO] setBackgroundColor:[NSColor redColor]];
        }
    }
    else if ([[tableColumn identifier] isEqualToString:@"status"])
    {
        if (status) {
            status = [NSString stringWithFormat:@"%@ %@", [APSettings settingForKeyPath:[@"statussymbols." stringByAppendingString:[status substringToIndex:1]]], status];
        }
        [cellView.imageView setHidden:YES];
        cellView.textField.stringValue = (status ? status : @"nil");
    }
    
    ABTIME_AVG_END(tableCellReload, 10, YES);
    
    return cellView;
}

-(void) controlTextDidChange:(NSNotification*)aNotification
{
    self.dataSource.filter = self.searchField.currentEditor.string;
}

@end
