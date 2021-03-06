//
//  NSPathControl.m
//  AppKit
//
//  Created by Fabian Spillner on 29.11.07.
//  Copyright 2007 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//
//  Implemented by Nikolaus Schaller on 03.03.08.
//

#import <AppKit/AppKit.h>

#import <AppKit/NSPathCell.h>
#import <AppKit/NSPathControl.h>

static Class __controlCellClass = Nil;

@implementation NSPathControl

+ (void) initialize
{
	if (self == [NSPathControl class])
		__controlCellClass = [NSPathCell class];
}

+ (Class) cellClass						{ return __controlCellClass; }
+ (void) setCellClass:(Class)aClass		{ __controlCellClass = aClass; }

- (id) initWithFrame:(NSRect) frame
{
	if((self=[super initWithFrame:frame]))
	{
		_localDraggingMask=NSDragOperationEvery;
		_remoteDraggingMask=NSDragOperationNone;
		// is it correct to add it here?
		// define tracking rects to call [cell _mouseEntered: and [cell _mouseExited:
		 _trackingTag = [self addTrackingRect:frame owner:self userData:NULL assumeInside:NO];
		// we must store the tag so that we can remove the tracking rect
		// JI: new ivar _trackingTag
		// FIXME: where do we remove? We need to implement - willMoveToWindow, acceptsFirstResponder and becomeFirstResponder
	}
	return self;
}

-(BOOL)acceptsFirstResponder { return YES; } //for the tracking rect

-(BOOL)becomeFirstResponder { return YES; } // for the tracking rect.

- (BOOL) isFlipped; { return YES; }

- (NSColor *) backgroundColor; { return [(NSPathCell *)_cell backgroundColor]; }
- (NSPathComponentCell *) clickedPathComponentCell; { return [(NSPathCell *)_cell clickedPathComponentCell]; }
- (id) delegate; { return _delegate; }
- (SEL) doubleAction; { return [(NSPathCell *)_cell doubleAction]; }
- (NSDragOperation) draggingSourceOperationMaskForLocal:(BOOL) flag; { return flag?_localDraggingMask:_remoteDraggingMask; }
- (NSArray *) pathComponentCells; { return [(NSPathCell *)_cell pathComponentCells]; }
- (NSPathStyle) pathStyle; { return [(NSPathCell *)_cell pathStyle]; }
- (void) setBackgroundColor:(NSColor *) col; { [(NSPathCell *)_cell setBackgroundColor:col]; }
- (void) setDelegate:(id) delegate; { _delegate=delegate; }
- (void) setDoubleAction:(SEL) sel; { [(NSPathCell *)_cell setDoubleAction:sel]; }
- (void) setDraggingSourceOperationMask:(NSDragOperation) mask forLocal:(BOOL) flag; { if(flag) _localDraggingMask=mask; else _remoteDraggingMask=mask; }
- (void) setPathComponentCells:(NSArray *) pathCells; { [(NSPathCell *)_cell setPathComponentCells:pathCells]; }
- (void) setPathStyle:(NSPathStyle) pathStyle; { [(NSPathCell *)_cell setPathStyle:pathStyle]; }
- (void) setURL:(NSURL *) url; { [(NSPathCell *)_cell setURL:url]; }
- (NSURL *) URL; { return [(NSPathCell *)_cell URL]; }

- (void) pathCell:(NSPathCell *) sender willDisplayOpenPanel:(NSOpenPanel *) openPanel; 
{ // forward to our delegate
	[_delegate pathControl:self willDisplayOpenPanel:openPanel]; 
}

- (void) pathCell:(NSPathCell *) sender willPopUpMenu:(NSMenu *) menu; 
{ // forward to our delegate
	[_delegate pathControl:self willPopUpMenu:menu]; 
}

- (void) mouseEntered:(NSEvent *)theEvent
{
	[[self cell] mouseEntered:theEvent withFrame:[self frame] inView:self];
}

- (void) mouseExited:(NSEvent *)theEvent
{
	[_cell mouseExited:theEvent withFrame:_frame inView:self];
}

- (void)viewWillMoveToWindow:(NSWindow *)win { //removes the trackingrect
    if (!win && [self window]) [self removeTrackingRect:_trackingTag];
    [super viewWillMoveToWindow:win];
}

- (id) initWithCoder:(NSCoder *) coder;
{
	return [super initWithCoder:coder];
}

@end

@implementation NSObject (NSPathControlDelegate)

- (BOOL) pathControl:(NSPathControl *) sender acceptDrop:(id <NSDraggingInfo>) draggingInfo;
{
	if([[sender cell] isEditable])
	{
		// accept if it contains NSURLPboardType or NSFilenamesPboardType which conforms to the cell allowed types.
	}
	return NO;	// refuse any drop
}

- (BOOL) pathControl:(NSPathControl *) sender shouldDragPathComponentCell:(NSPathComponentCell *) cell withPasteboard:(NSPasteboard *) pboard;
{
	if([[sender cell] isEditable])
	{
		// accept if it contains NSURLPboardType or NSFilenamesPboardType which conforms to the cell allowed types.
	}
	return NO;	// refuse any drop
}

- (NSDragOperation) pathControl:(NSPathControl *) sender validateDrop:(id <NSDraggingInfo>) draggingInfo;
{
	if([[sender cell] isEditable])
	{
		// accept if it contains NSURLPboardType or NSFilenamesPboardType which conforms to the cell allowed types.
	}
	return NSDragOperationNone;	// refuse any drop
}

- (void) pathControl:(NSPathControl *) sender willDisplayOpenPanel:(NSOpenPanel *) openPanel; { return; }
- (void) pathControl:(NSPathControl *) sender willPopUpMenu:(NSMenu *) menu; { return; }

@end

