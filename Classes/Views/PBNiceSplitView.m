//
//  PBNiceSplitView.m
//  GitX
//
//  Created by Pieter de Bie on 31-10-08.
//  Copyright 2008 Pieter de Bie. All rights reserved.
//

#import "PBNiceSplitView.h"

static NSImage *bar;
static NSImage *grip;

@implementation PBNiceSplitView

+(void) initialize
{
	NSString *barPath = [[NSBundle mainBundle] pathForResource:@"mainSplitterBar" ofType:@"tiff"];
	bar = [[NSImage alloc] initWithContentsOfFile: barPath];

	NSString *gripPath = [[NSBundle mainBundle] pathForResource:@"mainSplitterDimple" ofType:@"tiff"];
	grip = [[NSImage alloc] initWithContentsOfFile: gripPath];
}

- (void)drawDividerInRect:(NSRect)aRect
{
	// Draw bar and grip onto the canvas
	NSRect gripRect = aRect;
	gripRect.origin.y = (NSMidY(aRect) - ([grip size].height/2));
	gripRect.size.height = 2;
	
	[self lockFocus];
	//[bar drawInRect:aRect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0 respectFlipped:YES hints:nil];
	[grip drawInRect:gripRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0 respectFlipped:YES hints:nil];

	[self unlockFocus];
}

- (CGFloat)dividerThickness
{
	return 2.0;
}

@end
