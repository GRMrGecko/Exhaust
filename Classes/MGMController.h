//
//  MGMController.h
//  Exhaust
//
//  Created by Mr. Gecko on 8/7/10.
//  Copyright (c) 2011 Mr. Gecko's Media (James Coleman). All rights reserved. http://mrgeckosmedia.com/
//

#import <Cocoa/Cocoa.h>

#define exhaustdebug 0

@interface MGMController : NSObject {
	IBOutlet NSWindow *mainWindow;
	IBOutlet NSTableView *itemTable;
	IBOutlet NSButton *removeButton;
	IBOutlet NSButton *addButton;
	IBOutlet NSMenu *addMenu;
	
	NSMutableArray *startItems;
	NSMutableArray *loginItems;
	int itemIndex;
	BOOL shouldContinue;
	
	int selectedItem;
	IBOutlet NSTextField *commandField;
	IBOutlet NSButton *waitButton;
	IBOutlet NSTextField *delayField;
	IBOutlet NSTextField *quitField;
	IBOutlet NSTableView *argumentsTable;
	IBOutlet NSButton *argAddButton;
	IBOutlet NSButton *argRemoveButton;
	NSMutableArray *arguments;
	
	ProcessSerialNumber frontProcess;
	unsigned int windowCount;
	
	NSTimer *updateTimer;
	NSDate *lastModified;
}
- (void)registerDefaults;
- (NSString *)applicationSupportPath;

- (NSWindow *)mainWindow;
- (void)releaseMainWindow;

- (void)setFrontProcess:(ProcessSerialNumber *)theProcess;
- (void)becomeFront:(NSWindow *)theWindow;
- (void)resignFront;

- (void)loadItemsTo:(NSMutableArray **)theItems;
- (void)releaseStartItems;
- (void)releaseLoginItems;
- (BOOL)pathExists:(NSString *)thePath inItems:(NSMutableArray **)theItems;
- (void)startItems;
- (void)continueLaunching;
- (void)setEnabled:(BOOL)enabled;
- (IBAction)argAdd:(id)sender;
- (IBAction)argRemove:(id)sender;
- (IBAction)add:(id)sender;
- (IBAction)addApplication:(id)sender;
- (IBAction)addCommand:(id)sender;
- (IBAction)remove:(id)sender;

- (void)updateItems;

- (void)quit:(id)sender;
@end

@interface MGMBottomControl : NSView {
	
}

@end