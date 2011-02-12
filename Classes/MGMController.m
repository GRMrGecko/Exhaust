//
//  MGMController.m
//  Exhaust
//
//  Created by Mr. Gecko on 8/7/10.
//  Copyright (c) 2011 Mr. Gecko's Media (James Coleman). All rights reserved. http://mrgeckosmedia.com/
//

#import "MGMController.h"
#import "MGMFileManager.h"
#import "MGMLoginItems.h"
#import "MGMAddons.h"
#import <GeckoReporter/GeckoReporter.h>
#import <Carbon/Carbon.h>

NSString * const MGMApplicationSupport = @"~/Library/Application Support/MrGeckosMedia/";
NSString * const MGMSaveFile = @"loginItems.plist";

NSString * const MGMCommandKey = @"command";
NSString * const MGMWaitKey = @"wait";
NSString * const MGMDelayKey = @"delay";
NSString * const MGMQuitKey = @"quit";
NSString * const MGMArgumentsKey = @"arguments";
NSString * const MGMShouldContinueKey = @"shouldContinue";
NSString * const MGMIsApplicationKey = @"isApplication";

NSString * const MGMMacOS = @"MacOS";
NSString * const MGMSelfName = @"Exhaust.app";

NSString * const MGMTableDragType = @"MGMTableDragType";
NSString * const MGMArgTableDragType = @"MGMArgTableDragType";

NSString * const MGMFirstLaunch = @"firstLaunch";
NSString * const MGMLaunchCount = @"launchCount";

OSStatus frontAppChanged(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
	ProcessSerialNumber thisProcess;
	GetCurrentProcess(&thisProcess);
	ProcessSerialNumber newProcess;
	GetFrontProcess(&newProcess);
	Boolean same;
	SameProcess(&newProcess, &thisProcess, &same);
	if (!same)
		[(MGMController *)userData setFrontProcess:&newProcess];
    return (CallNextEventHandler(nextHandler, theEvent));
}

@protocol NSSavePanelProtocol <NSObject>
- (void)setDirectoryURL:(NSURL *)url;
@end

@implementation MGMController
- (void)applicationDidFinishLaunching:(NSNotification *)theNotification {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setup) name:MGMGRDoneNotification object:nil];
	[MGMReporter sharedReporter];
}
- (void)setup {
	lastModified = nil;
	NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
	[workspaceCenter addObserver:self selector:@selector(willLogout:) name:NSWorkspaceWillPowerOffNotification object:nil];
	[workspaceCenter addObserver:self selector:@selector(applicationDidLaunch:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
	[self registerDefaults];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults boolForKey:MGMFirstLaunch]) {
		NSAlert *alert = [[NSAlert new] autorelease];
		[alert setMessageText:NSLocalizedString(@"Welcome to Exhaust", nil)];
		[alert setInformativeText:NSLocalizedString(@"Exhaust can be complicated at times, please be sure you read the documentation even if your the type of person who thinks he/she doesn't need to read documentation. If you haven't read the documentation, please quit now and read it.", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", nil)];
		int result = [alert runModal];
		if (result==1000) {
			exit(0);
			return;
		} else if (result==1001) {
			[defaults setBool:NO forKey:MGMFirstLaunch];
		}
	}
	
	EventTypeSpec eventType;
	eventType.eventClass = kEventClassApplication;
	eventType.eventKind = kEventAppFrontSwitched;
	EventHandlerUPP handlerUPP = NewEventHandlerUPP(frontAppChanged);
	InstallApplicationEventHandler(handlerUPP, 1, &eventType, self, NULL);
	
	if ([[MGMLoginItems items] selfExists]) {
		[self startItems];
	} else {
		[[self mainWindow] makeKeyAndOrderFront:self];
		[self becomeFront:[self mainWindow]];
	}
	
	updateTimer = [[NSTimer scheduledTimerWithTimeInterval:3600 target:self selector:@selector(updateItems) userInfo:nil repeats:YES] retain];
}
- (void)dealloc {
	DisposeEventHandlerUPP(frontAppChanged);
	[self releaseStartItems];
	[self releaseMainWindow];
	[updateTimer invalidate];
	[updateTimer release];
	[super dealloc];
}

- (void)registerDefaults {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults setObject:[NSNumber numberWithBool:YES] forKey:MGMFirstLaunch];
	[defaults setObject:[NSNumber numberWithInt:1] forKey:MGMLaunchCount];
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

- (NSString *)applicationSupportPath {
	NSString *applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleExecutableKey];
	NSString *applicationSupport = [[MGMApplicationSupport stringByExpandingTildeInPath] stringByAppendingPathComponent:applicationName];
	NSFileManager *manager = [NSFileManager defaultManager];
	if (![manager fileExistsAtPath:applicationSupport])
		[manager createDirectoryAtPath:applicationSupport withAttributes:nil];
	return applicationSupport;
}

- (NSWindow *)mainWindow {
	if (mainWindow==nil) {
		if (![NSBundle loadNibNamed:@"ExuastWindow" owner:self]) {
			NSLog(@"Unable to load the window.");
		} else {
			arguments = [NSMutableArray new];
			[self loadItemsTo:&loginItems];
			[itemTable registerForDraggedTypes:[NSArray arrayWithObjects:MGMTableDragType, NSFilenamesPboardType, nil]];
			[argumentsTable registerForDraggedTypes:[NSArray arrayWithObject:MGMArgTableDragType]];
			[self setEnabled:NO];
			[removeButton setEnabled:NO];
			selectedItem = -1;
			[itemTable reloadData];
			[mainWindow setLevel:NSFloatingWindowLevel];
		}
	}
	return mainWindow;
}
- (void)releaseMainWindow {
	[self releaseLoginItems];
	[arguments release];
	arguments = nil;
	[mainWindow release];
	mainWindow = nil;
	itemTable = nil;
	removeButton = nil;
	addButton = nil;
	addMenu = nil;
	commandField = nil;
	waitButton = nil;
	delayField = nil;
	quitField = nil;
	argumentsTable = nil;
	argAddButton = nil;
	argRemoveButton = nil;
}

- (void)setFrontProcess:(ProcessSerialNumber *)theProcess {
	frontProcess = *theProcess;
	/*CFStringRef name;
	CopyProcessName(theProcess, &name);
	if (name!=NULL) {
		NSLog(@"%@ became front", (NSString *)name);
		CFRelease(name);
	}*/
}
- (void)becomeFront:(NSWindow *)theWindow {
	if (theWindow!=nil) {
		windowCount++;
		if ([[MGMSystemInfo info] isUIElement])
			[theWindow setLevel:NSFloatingWindowLevel];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frontWindowClosed:) name:NSWindowWillCloseNotification object:theWindow];
	}
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}
- (void)resignFront {
	SetFrontProcess(&frontProcess);
	//[[NSApplication sharedApplication] hide:self];
}
- (void)frontWindowClosed:(NSNotification *)theNotification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:[theNotification name] object:[theNotification object]];
	windowCount--;
	if (windowCount==0)
		[self resignFront];
}

- (void)loadItemsTo:(NSMutableArray **)theItems {
	NSFileManager *manager = [NSFileManager defaultManager];
	[*theItems release];
	*theItems = nil;
	if ([manager fileExistsAtPath:[[self applicationSupportPath] stringByAppendingPathComponent:MGMSaveFile]]) {
		*theItems = [[NSMutableArray arrayWithContentsOfFile:[[self applicationSupportPath] stringByAppendingPathComponent:MGMSaveFile]] retain];
	} else {
		*theItems = [NSMutableArray new];
	}
	MGMLoginItems *items = [MGMLoginItems items];
	[items removeSelf];
	NSArray *paths = [items paths];
	for (int i=0; i<[paths count]; i++) {
		if ([[[paths objectAtIndex:i] lastPathComponent] isEqual:MGMSelfName])
			continue;
		NSString *path = [[NSBundle bundleWithPath:[paths objectAtIndex:i]] executablePath];
		if ([manager fileExistsAtPath:path] && [manager isExecutableFileAtPath:path] && ![self pathExists:path inItems:theItems]) {
			NSMutableDictionary *info = [NSMutableDictionary dictionary];
			[info setObject:path forKey:MGMCommandKey];
			[info setObject:[NSNumber numberWithBool:NO] forKey:MGMWaitKey];
			[info setObject:[NSArray array] forKey:MGMArgumentsKey];
			[*theItems addObject:info];
		}
		[items remove:[paths objectAtIndex:i]];
	}
	[items addSelf];
	[lastModified release];
	lastModified = nil;
	NSDictionary *attributes = [manager attributesOfItemAtPath:[MGMLoginItemsPath stringByExpandingTildeInPath]];
	if ([attributes objectForKey:NSFileModificationDate]!=nil)
		lastModified = [[attributes objectForKey:NSFileModificationDate] retain];
}
- (void)releaseStartItems {
	[startItems writeToFile:[[self applicationSupportPath] stringByAppendingPathComponent:MGMSaveFile] atomically:YES];
	[startItems release];
	startItems = nil;
}
- (void)releaseLoginItems {
	if (selectedItem!=-1) {
		NSFileManager *manager = [NSFileManager defaultManager];
		if (![[commandField stringValue] isEqual:@""] && [manager fileExistsAtPath:[commandField stringValue]] && [manager isExecutableFileAtPath:[commandField stringValue]]) {
			NSMutableDictionary *info = [NSMutableDictionary dictionary];
			[info setObject:[commandField stringValue] forKey:MGMCommandKey];
			[info setObject:[NSNumber numberWithBool:([waitButton state]==NSOnState ? YES : NO)] forKey:MGMWaitKey];
			if ([delayField intValue]!=0)
				[info setObject:[NSNumber numberWithFloat:[delayField floatValue]] forKey:MGMDelayKey];
			if ([quitField intValue]!=0)
				[info setObject:[NSNumber numberWithFloat:[quitField floatValue]] forKey:MGMQuitKey];
			[info setObject:arguments forKey:MGMArgumentsKey];
			[loginItems replaceObjectAtIndex:selectedItem withObject:info];
		}
		[itemTable deselectAll:self];
	}
	[itemTable reloadData];
	[loginItems writeToFile:[[self applicationSupportPath] stringByAppendingPathComponent:MGMSaveFile] atomically:YES];
	[loginItems release];
	loginItems = nil;
}
- (BOOL)pathExists:(NSString *)thePath inItems:(NSMutableArray **)theItems {
	for (int i=0; i<[*theItems count]; i++) {
		if ([[[*theItems objectAtIndex:i] objectForKey:MGMCommandKey] isEqual:thePath])
			return YES;
	}
	return NO;
}

- (void)startItems {
	[self loadItemsTo:&startItems];
	itemIndex = 0;
	[self continueLaunching];
}
- (void)continueLaunching {
	NSFileManager *manager = [NSFileManager defaultManager];
	for (; itemIndex<[startItems count]; itemIndex++) {
		NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:[startItems objectAtIndex:itemIndex]];
#if exhaustdebug
		NSLog(@"%d %@", itemIndex, [[info objectForKey:MGMCommandKey] lastPathComponent]);
#endif
		shouldContinue = YES;
		BOOL isApplication = NO;
		NSString *path = [info objectForKey:MGMCommandKey];
		if ([[[path stringByDeletingLastPathComponent] lastPathComponent] isEqual:MGMMacOS]) {
			path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
			NSBundle *bundle = [NSBundle bundleWithPath:path];
			if (bundle!=nil && ![[bundle objectForInfoDictionaryKey:@"LSUIElement"] boolValue]) {
				isApplication = YES;
#if exhaustdebug
				NSLog(@"We are a application");
#endif
			}
		}
		if (![manager fileExistsAtPath:[info objectForKey:MGMCommandKey]] || ![manager isExecutableFileAtPath:[info objectForKey:MGMCommandKey]]) {
			[startItems removeObjectAtIndex:itemIndex];
			itemIndex--;
			continue;
		}
		if ((itemIndex+1)<[startItems count] && [[[startItems objectAtIndex:itemIndex+1] objectForKey:MGMWaitKey] boolValue]) {
			shouldContinue = NO;
#if exhaustdebug
			NSLog(@"We should not continue");
#endif
		}
		
		if ([info objectForKey:MGMDelayKey]!=nil) {
#if exhaustdebug
			NSLog(@"We should Delay for %@ seconds", [info objectForKey:MGMDelayKey]);
#endif
			[info setObject:[NSNumber numberWithBool:shouldContinue] forKey:MGMShouldContinueKey];
			[info setObject:[NSNumber numberWithBool:isApplication] forKey:MGMIsApplicationKey];
			[NSTimer scheduledTimerWithTimeInterval:[[info objectForKey:MGMDelayKey] floatValue] target:self selector:@selector(startItem:) userInfo:info repeats:NO];
		} else {
			@try {
				NSTask *theTask = [NSTask launchedTaskWithLaunchPath:[info objectForKey:MGMCommandKey] arguments:[info objectForKey:MGMArgumentsKey]];
				if (!isApplication && !shouldContinue) {
					itemIndex++;
#if exhaustdebug
					NSLog(@"We will continue in 15 seconds");
#endif
					[NSTimer scheduledTimerWithTimeInterval:15.0 target:self selector:@selector(continueLaunching) userInfo:nil repeats:NO];
				}
				if ([info objectForKey:MGMQuitKey]!=nil) {
#if exhaustdebug
					NSLog(@"We will quit in %@ seconds", [info objectForKey:MGMQuitKey]);
#endif
					[NSTimer scheduledTimerWithTimeInterval:[[info objectForKey:MGMQuitKey] floatValue] target:self selector:@selector(quitItem:) userInfo:theTask repeats:NO];
				}
			}
			@catch (NSException *e) {
				NSLog(@"Unable to start %@: %@", [info objectForKey:MGMCommandKey], e);
			}
		}
		
		if (!shouldContinue)
			break;
#if exhaustdebug
		NSLog(@"We are going on as we are continuing.");
#endif
	}
	
	if (itemIndex>=[startItems count]) {
		[self releaseStartItems];
		[self performSelector:@selector(updateItems) withObject:nil afterDelay:300];
	}
}
- (void)startItem:(NSTimer *)timer {
	NSDictionary *info = [timer userInfo];
	@try {
		NSTask *theTask = [NSTask launchedTaskWithLaunchPath:[[timer userInfo] objectForKey:MGMCommandKey] arguments:[[timer userInfo] objectForKey:MGMArgumentsKey]];
		if (![[info objectForKey:MGMIsApplicationKey] boolValue] && ![[info objectForKey:MGMShouldContinueKey] boolValue]) {
			itemIndex++;
#if exhaustdebug
			NSLog(@"We will continue in 15 seconds");
#endif
			[NSTimer scheduledTimerWithTimeInterval:15.0 target:self selector:@selector(continueLaunching) userInfo:nil repeats:NO];
		}
		if ([info objectForKey:MGMQuitKey]!=nil) {
#if exhaustdebug
			NSLog(@"We will quit in %@ seconds", [info objectForKey:MGMQuitKey]);
#endif
			[NSTimer scheduledTimerWithTimeInterval:[[info objectForKey:MGMQuitKey] floatValue] target:self selector:@selector(quitItem:) userInfo:theTask repeats:NO];
		}
	}
	@catch (NSException *e) {
		NSLog(@"Unable to start %@: %@", [[timer userInfo] objectForKey:MGMCommandKey], e);
	}
}
- (void)quitItem:(NSTimer *)timer {
	[(NSTask *)[timer userInfo] terminate];
}
- (void)applicationDidLaunch:(NSNotification *)theNotification {
	if (!shouldContinue) {
		NSString *path = [[startItems objectAtIndex:itemIndex] objectForKey:MGMCommandKey];
		if ([[[path stringByDeletingLastPathComponent] lastPathComponent] isEqual:MGMMacOS]) {
			path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
		}
		if ([[[theNotification userInfo] objectForKey:@"NSApplicationPath"] isEqual:path]) {
#if exhaustdebug
			NSLog(@"%@ launched, let's continue in 5 seconds.", [path lastPathComponent]);
#endif
			itemIndex++;
			[NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(continueLaunching) userInfo:nil repeats:NO];
		}
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	[[self mainWindow] makeKeyAndOrderFront:self];
	[self becomeFront:[self mainWindow]];
	if (!flag) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		if ([defaults integerForKey:MGMLaunchCount]!=3) {
			[defaults setInteger:[defaults integerForKey:MGMLaunchCount]+1 forKey:MGMLaunchCount];
			if ([defaults integerForKey:MGMLaunchCount]==3) {
				NSAlert *alert = [[NSAlert new] autorelease];
				[alert setMessageText:NSLocalizedString(@"Donations", nil)];
				[alert setInformativeText:NSLocalizedString(@"Thank you for using Exhast, if you like Exhaust, consider sending a donation.", nil)];
				[alert addButtonWithTitle:NSLocalizedString(@"Yes", nil)];
				[alert addButtonWithTitle:NSLocalizedString(@"No", nil)];
				int result = [alert runModal];
				if (result==1000)
					[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MGCBN8NHD8VQW"]];
			}
		}
	}
	return YES;
}

- (void)setEnabled:(BOOL)enabled {
	[commandField setEnabled:enabled];
	[waitButton setEnabled:enabled];
	[delayField setEnabled:enabled];
	[quitField setEnabled:enabled];
	[argumentsTable setEnabled:enabled];
	[argAddButton setEnabled:enabled];
	[argRemoveButton setEnabled:enabled];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)theTableView {
	if (theTableView==itemTable) {
		return [loginItems count];
	} else if (theTableView==argumentsTable) {
		return [arguments count];
	}
	return 0;
}
- (id)tableView:(NSTableView *)theTableView objectValueForTableColumn:(NSTableColumn *)theTableColumn row:(NSInteger)theRowIndex {
	if (theTableView==itemTable) {
		NSDictionary *info = [loginItems objectAtIndex:theRowIndex];
		if ([[theTableColumn identifier] isEqual:@"name"]) {
			return [[info objectForKey:MGMCommandKey] lastPathComponent];
		} else if ([[theTableColumn identifier] isEqual:@"icon"]) {
			NSString *path = [info objectForKey:MGMCommandKey];
			if ([[[path stringByDeletingLastPathComponent] lastPathComponent] isEqual:MGMMacOS]) {
				path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
			}
			return [[NSWorkspace sharedWorkspace] iconForFile:path];
		}
	} else if (theTableView==argumentsTable) {
		return [arguments objectAtIndex:theRowIndex];
	}
	return nil;
}
- (void)tableView:(NSTableView *)theTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)theTableColumn row:(NSInteger)theRowIndex {
	if (theTableView==argumentsTable)
		[arguments replaceObjectAtIndex:theRowIndex withObject:anObject];
}
- (BOOL)tableView:(NSTableView *)theTableView writeRowsWithIndexes:(NSIndexSet *)theRowIndexes toPasteboard:(NSPasteboard *)thePboard {
	if (theTableView==itemTable) {
		NSMutableArray *items = [NSMutableArray array];
		long index = [theRowIndexes lastIndex];
		while (index!=NSNotFound) {
			NSDictionary *item = [loginItems objectAtIndex:index];
			[items addObject:item];
			index = [theRowIndexes indexLessThanIndex:index];
		}
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:items];
		[thePboard declareTypes:[NSArray arrayWithObject:MGMTableDragType] owner:self];
		[thePboard setData:data forType:MGMTableDragType];
		[itemTable deselectAll:self];
	} else if (theTableView==argumentsTable) {
		NSMutableArray *items = [NSMutableArray array];
		long index = [theRowIndexes lastIndex];
		while (index!=NSNotFound) {
			NSDictionary *item = [arguments objectAtIndex:index];
			[items addObject:item];
			index = [theRowIndexes indexLessThanIndex:index];
		}
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:items];
		[thePboard declareTypes:[NSArray arrayWithObject:MGMArgTableDragType] owner:self];
		[thePboard setData:data forType:MGMArgTableDragType];
		[argumentsTable deselectAll:self];
	}
	return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
	return NSDragOperationEvery;
}
- (BOOL)tableView:(NSTableView *)theTableView acceptDrop:(id < NSDraggingInfo >)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
	if (theTableView==itemTable) {
		if ([[info draggingPasteboard] dataForType:MGMTableDragType]!=nil) {
			NSArray *items = [NSKeyedUnarchiver unarchiveObjectWithData:[[info draggingPasteboard] dataForType:MGMTableDragType]];
			for (int i=0; i<[items count]; i++) {
				int index = [loginItems indexOfObject:[items objectAtIndex:i]];
				if (row>=index)
					row--;
				[loginItems removeObjectAtIndex:index];
			}
			[itemTable reloadData];
			for (long i=0; i<[items count]; i++) {
				[loginItems insertObject:[items objectAtIndex:i] atIndex:row];
			}
			[itemTable reloadData];
			[itemTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
			return YES;
		} else if ([[info draggingPasteboard] propertyListForType:NSFilenamesPboardType]!=nil) {
			NSArray *paths = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
			BOOL foundResults = NO;
			for (int i=0; i<[paths count]; i++) {
				if ([[[[paths objectAtIndex:i] pathExtension] lowercaseString] isEqual:@"app"]) {
					if ([[[paths objectAtIndex:i] lastPathComponent] isEqual:MGMSelfName])
						return NO;
					NSString *path = [[NSBundle bundleWithPath:[paths objectAtIndex:i]] executablePath];
					NSFileManager *manager = [NSFileManager defaultManager];
					if ([manager fileExistsAtPath:path] && [manager isExecutableFileAtPath:path] && ![self pathExists:path inItems:&loginItems]) {
						foundResults = YES;
						NSMutableDictionary *info = [NSMutableDictionary dictionary];
						[info setObject:path forKey:MGMCommandKey];
						[info setObject:[NSNumber numberWithBool:NO] forKey:MGMWaitKey];
						[info setObject:[NSArray array] forKey:MGMArgumentsKey];
						[loginItems addObject:info];
						[itemTable reloadData];
						[itemTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[loginItems count]-1] byExtendingSelection:NO];
					}
				}
			}
			return foundResults;
		}
	} else if (theTableView==argumentsTable) {
		if ([[info draggingPasteboard] dataForType:MGMArgTableDragType]!=nil) {
			NSArray *items = [NSKeyedUnarchiver unarchiveObjectWithData:[[info draggingPasteboard] dataForType:MGMArgTableDragType]];
			for (int i=0; i<[items count]; i++) {
				int index = [arguments indexOfObject:[items objectAtIndex:i]];
				if (row>=index)
					row--;
				[arguments removeObjectAtIndex:index];
			}
			[argumentsTable reloadData];
			for (int i=0; i<[items count]; i++) {
				[arguments insertObject:[items objectAtIndex:i] atIndex:row];
			}
			[argumentsTable reloadData];
			[argumentsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
			return YES;
		}
	}
	return NO;
}
- (void)tableViewSelectionDidChange:(NSNotification *)theNotification {
	if ([theNotification object]==itemTable) {
		[removeButton setEnabled:YES];
		if (selectedItem!=-1) {
			NSFileManager *manager = [NSFileManager defaultManager];
			if ([[commandField stringValue] isEqual:@""] || ![manager fileExistsAtPath:[commandField stringValue]] || ![manager isExecutableFileAtPath:[commandField stringValue]]) {
				NSBeep();
			} else {
				NSMutableDictionary *info = [NSMutableDictionary dictionary];
				[info setObject:[commandField stringValue] forKey:MGMCommandKey];
				[info setObject:[NSNumber numberWithBool:([waitButton state]==NSOnState ? YES : NO)] forKey:MGMWaitKey];
				if ([delayField intValue]!=0)
					[info setObject:[NSNumber numberWithFloat:[delayField floatValue]] forKey:MGMDelayKey];
				if ([quitField intValue]!=0)
					[info setObject:[NSNumber numberWithFloat:[quitField floatValue]] forKey:MGMQuitKey];
				[info setObject:arguments forKey:MGMArgumentsKey];
				[loginItems replaceObjectAtIndex:selectedItem withObject:info];
			}
		}
		if ([[itemTable selectedRowIndexes] count]==1) {
			[self setEnabled:YES];
			selectedItem = [itemTable selectedRow];
			NSDictionary *info = [loginItems objectAtIndex:selectedItem];
			[commandField setStringValue:[info objectForKey:MGMCommandKey]];
			[waitButton setState:([[info objectForKey:MGMWaitKey] boolValue] ? NSOnState : NSOffState)];
			if ([info objectForKey:MGMDelayKey]==nil)
				[delayField setStringValue:@""];
			else
				[delayField setIntValue:[[info objectForKey:MGMDelayKey] floatValue]];
			if ([info objectForKey:MGMQuitKey]==nil)
				[quitField setStringValue:@""];
			else
				[quitField setIntValue:[[info objectForKey:MGMQuitKey] floatValue]];
			if (arguments!=nil) [arguments release];
			arguments = [[NSMutableArray arrayWithArray:[info objectForKey:MGMArgumentsKey]] retain];
			[argRemoveButton setEnabled:NO];
		} else {
			selectedItem = -1;
			[commandField setStringValue:@""];
			[waitButton setState:NSOffState];
			[delayField setStringValue:@""];
			[quitField setStringValue:@""];
			if (arguments!=nil) [arguments release];
			arguments = [NSMutableArray new];
			if ([[itemTable selectedRowIndexes] count]==0) {
				[removeButton setEnabled:NO];
			}
			[self setEnabled:NO];
		}
		[argumentsTable reloadData];
	} else if ([theNotification object]==argumentsTable) {
		[argRemoveButton setEnabled:([[argumentsTable selectedRowIndexes] count]!=0)];
	}
}

- (IBAction)argAdd:(id)sender {
	[arguments addObject:@""];
	[argumentsTable reloadData];
	[argumentsTable editColumn:0 row:[arguments count]-1 withEvent:nil select:YES];
}
- (IBAction)argRemove:(id)sender {
	[arguments removeObjectAtIndex:[argumentsTable selectedRow]];
	[argumentsTable reloadData];
}

- (IBAction)add:(id)sender {
	NSPoint location = [addButton frame].origin;
	location.y += 20;
	NSEvent *event = [NSEvent mouseEventWithType:NSLeftMouseUp location:location modifierFlags:0 timestamp:0 windowNumber:[mainWindow windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0];
	[NSMenu popUpContextMenu:addMenu withEvent:event forView:addButton];
}
- (IBAction)addApplication:(id)sender {
	NSOpenPanel<NSSavePanelProtocol> *panel = [NSOpenPanel openPanel];
	[panel setCanChooseFiles:YES];
	[panel setCanChooseDirectories:NO];
	[panel setResolvesAliases:YES];
	[panel setAllowsMultipleSelection:NO];
	[panel setAllowedFileTypes:[NSArray arrayWithObject:@"app"]];
	[panel setTreatsFilePackagesAsDirectories:NO];
	int returnCode;
	if ([panel respondsToSelector:@selector(runModalForDirectory:file:)]) {
		returnCode = [panel runModalForDirectory:@"/Applications/" file:nil];
	} else {
		[panel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications/"]];
		returnCode = [panel runModal];
	}
	if (returnCode==NSOKButton) {
		if ([[[[panel URL] path] lastPathComponent] isEqual:MGMSelfName])
			return;
		NSString *path = [[NSBundle bundleWithPath:[[panel URL] path]] executablePath];
		NSFileManager *manager = [NSFileManager defaultManager];
		if ([manager fileExistsAtPath:path] && [manager isExecutableFileAtPath:path] && ![self pathExists:path inItems:&loginItems]) {
			NSMutableDictionary *info = [NSMutableDictionary dictionary];
			[info setObject:path forKey:MGMCommandKey];
			[info setObject:[NSNumber numberWithBool:NO] forKey:MGMWaitKey];
			[info setObject:[NSArray array] forKey:MGMArgumentsKey];
			[loginItems addObject:info];
			[itemTable reloadData];
			[itemTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[loginItems count]-1] byExtendingSelection:NO];
		}
	}
}
- (IBAction)addCommand:(id)sender {
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[info setObject:@"/bin/bash" forKey:MGMCommandKey];
	[info setObject:[NSNumber numberWithBool:NO] forKey:MGMWaitKey];
	[info setObject:[NSArray arrayWithObject:@"-c"] forKey:MGMArgumentsKey];
	[loginItems addObject:info];
	[itemTable reloadData];
	[itemTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[loginItems count]-1] byExtendingSelection:NO];
}
- (IBAction)remove:(id)sender {
	NSIndexSet *indexes = [itemTable selectedRowIndexes];
	if ([indexes count]==1) {
		[loginItems removeObjectAtIndex:[itemTable selectedRow]];
	} else {
		NSMutableArray *items = [NSMutableArray new];
		long index = [indexes lastIndex];
		while (index!=NSNotFound) {
			[items addObject:[loginItems objectAtIndex:index]];
			index = [indexes indexLessThanIndex:index];
		}
		for (int i=0; i<[items count]; i++) {
			[loginItems removeObject:[items objectAtIndex:i]];
		}
		[items release];
	}
	selectedItem = -1;
	[itemTable reloadData];
	[itemTable deselectAll:self];
}

- (void)updateItems {
	if (loginItems==nil && startItems==nil) {
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[MGMLoginItemsPath stringByExpandingTildeInPath]];
		NSDate *modifiedDate = [attributes objectForKey:NSFileModificationDate];
		if (modifiedDate!=nil || lastModified==nil || (![modifiedDate isEqual:lastModified] && [modifiedDate laterDate:lastModified]==modifiedDate)) {
			[self loadItemsTo:&startItems];
			[self releaseStartItems];
		}
	}
}

- (void)windowWillClose:(NSNotification *)theNotification {
	[self releaseMainWindow];
}

- (void)willLogout:(NSNotification *)theNotification {
	if (mainWindow!=nil) [self releaseMainWindow];
	[self releaseStartItems];
	[self updateItems];
}
- (void)updaterWillRelaunchApplication {
	MGMLoginItems *items = [MGMLoginItems items];
	[items removeSelf];
	if (mainWindow!=nil) [self releaseMainWindow];
	if (startItems==nil) [self loadItemsTo:&startItems];
	for (int i=0; i<[startItems count]; i++) {
		NSString *path = [[startItems objectAtIndex:i] objectForKey:MGMCommandKey];
		if ([[[path stringByDeletingLastPathComponent] lastPathComponent] isEqual:MGMMacOS]) {
			path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
			NSBundle *bundle = [NSBundle bundleWithPath:path];
			if (bundle!=nil) {
				[items add:path];
			}
		}
	}
}
- (void)quit:(id)sender {
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Are you sure you want to quit?", nil)];
	[alert setInformativeText:NSLocalizedString(@"When you quit, you will remove all items and place it back into Apple's login system. Are you sure you want to do that? If not just hit cancel and close the window instead.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
	int returnValue = [alert runModal];
	if (returnValue==1000) {
		MGMLoginItems *items = [MGMLoginItems items];
		[items removeSelf];
		if (mainWindow!=nil) [self releaseMainWindow];
		if (startItems==nil) [self loadItemsTo:&startItems];
		for (int i=0; i<[startItems count]; i++) {
			NSString *path = [[startItems objectAtIndex:i] objectForKey:MGMCommandKey];
			if ([[[path stringByDeletingLastPathComponent] lastPathComponent] isEqual:MGMMacOS]) {
				path = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
				NSBundle *bundle = [NSBundle bundleWithPath:path];
				if (bundle!=nil) {
					[items add:path];
				}
			}
		}
		[[NSApplication sharedApplication] terminate:self];
	}
}
@end

@implementation MGMBottomControl
- (void)drawRect:(NSRect)rect {
	NSBezierPath *path = [NSBezierPath bezierPathWithRect:[self frame]];
	[path fillGradientFrom:[NSColor colorWithCalibratedWhite:0.992156 alpha:1.0] to:[NSColor colorWithCalibratedWhite:0.886274 alpha:1.0]];
}
@end