static NSString *
AppName(void)
{
	NSBundle *bundle = [NSBundle mainBundle];
	return [bundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
}

static NSMenu *
CreateMenu(void)
{
	NSMenu *menuBar = [[NSMenu alloc] init];

	NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
	[menuBar addItem:appMenuItem];

	NSMenu *appMenu = [[NSMenu alloc] init];
	appMenuItem.submenu = appMenu;

	NSString *quitMenuItemTitle = [NSString stringWithFormat:@"Quit %@", AppName()];
	NSMenuItem *quitMenuItem = [[NSMenuItem alloc] initWithTitle:quitMenuItemTitle
	                                                      action:@selector(terminate:)
	                                               keyEquivalent:@"q"];

	[appMenu addItem:quitMenuItem];

	return menuBar;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
	NSWindow *window;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSApp.mainMenu = CreateMenu();

	NSRect rect = NSMakeRect(100, 100, 1000, 700);

	NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
	                          NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
	window = [[NSWindow alloc] initWithContentRect:rect
	                                     styleMask:style
	                                       backing:NSBackingStoreBuffered
	                                         defer:NO];

	window.contentViewController = [[MainViewController alloc] init];
	window.title = @"FastGaussianBlur";

	[window makeKeyAndOrderFront:nil];
	[NSApp activate];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

@end
