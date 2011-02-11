//
//  MGMAddons.h
//  Exhaust
//
//  Created by Mr. Gecko on 2/8/11.
//  Copyright (c) 2011 Mr. Gecko's Media (James Coleman). All rights reserved. http://mrgeckosmedia.com/
//

#import <Foundation/Foundation.h>

@interface NSBezierPath (MGMAddons)
+ (NSBezierPath *)pathWithRect:(NSRect)theRect radiusX:(float)theRadiusX radiusY:(float)theRadiusY;
- (void)fillGradientFrom:(NSColor *)theStartColor to:(NSColor *)theEndColor;
@end