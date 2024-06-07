@interface MainViewController : NSTabViewController <NSToolbarDelegate>
@end

@implementation MainViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.tabStyle = NSTabViewControllerTabStyleUnspecified;

	[self addChildViewController:[[MetalViewController alloc] init]];
	[self addChildViewController:[[BenchmarksViewController alloc] init]];

	for (NSViewController *childViewController in self.childViewControllers)
	{
		NSTabViewItem *item = [self tabViewItemForViewController:childViewController];
		[item bind:NSLabelBinding
		           toObject:childViewController
		        withKeyPath:@"title"
		            options:nil];
	}
}

- (void)viewDidAppear
{
	NSToolbar *toolbar = [[NSToolbar alloc] init];
	toolbar.delegate = self;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;
	self.view.window.toolbar = toolbar;
}

- (void)tabPickerDidSelectTab:(NSToolbarItemGroup *)sender
{
	self.selectedTabViewItemIndex = sender.selectedIndex;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
            itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
        willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([itemIdentifier isEqualToString:@"TabPicker"])
	{
		NSMutableArray<NSString *> *titles = [[NSMutableArray alloc] init];
		for (NSTabViewItem *item in self.tabViewItems)
		{
			[titles addObject:item.label];
		}

		NSToolbarItemGroup *item = [NSToolbarItemGroup
		        groupWithItemIdentifier:@"TabPicker"
		                         titles:titles
		                  selectionMode:NSToolbarItemGroupSelectionModeSelectOne
		                         labels:titles
		                         target:self
		                         action:@selector(tabPickerDidSelectTab:)];
		item.selectedIndex = 0;
		return item;
	}

	return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[ @"TabPicker" ];
}

#pragma clang diagnostic pop

@end
