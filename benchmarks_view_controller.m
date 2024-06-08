@interface BenchmarksViewController : NSViewController
{
	NSStackView *stackView;
	NSProgressIndicator *progressIndicator;
	NSTableView *resultsTableView;
	NSTableViewDiffableDataSource *dataSource;
}
@end

@interface CellId : NSObject
@property NSString *benchmarkRunner;
@property double averageDuration;
@end

@implementation CellId
@end

@implementation BenchmarksViewController

NSString *RunnerNameColumnIdentifier = @"RunnerName";
NSString *DurationColumnIdentifier = @"Duration";

- (instancetype)init
{
	self = [super init];
	self.title = @"Benchmarks";
	return self;
}

- (void)viewDidLoad
{
	stackView = [[NSStackView alloc] init];
	stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
	stackView.alignment = NSLayoutAttributeLeading;

	[self.view addSubview:stackView];
	stackView.translatesAutoresizingMaskIntoConstraints = NO;
	[NSLayoutConstraint activateConstraints:@[
		[stackView.topAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.topAnchor],
		[stackView.leadingAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
		[stackView.trailingAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
		[stackView.bottomAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.bottomAnchor],
	]];

	NSButton *runBenchmarkButton = [NSButton buttonWithTitle:@"Run Benchmark"
	                                                  target:self
	                                                  action:@selector(didPressRunBenchmarks:)];
	[stackView addArrangedSubview:runBenchmarkButton];

	progressIndicator = [[NSProgressIndicator alloc] init];
	[stackView addArrangedSubview:progressIndicator];

	[self configureResultsTable];
}

- (void)configureResultsTable
{
	resultsTableView = [[NSTableView alloc] init];
	resultsTableView.allowsColumnReordering = NO;

	NSTableColumn *runnerNameColumn =
	        [[NSTableColumn alloc] initWithIdentifier:RunnerNameColumnIdentifier];
	NSTableColumn *durationColumn =
	        [[NSTableColumn alloc] initWithIdentifier:DurationColumnIdentifier];

	runnerNameColumn.title = @"Benchmark Runner";
	durationColumn.title = @"Duration (ms)";

	runnerNameColumn.width = 150;
	durationColumn.width = 100;

	runnerNameColumn.resizingMask = 0;
	durationColumn.resizingMask = 0;

	[resultsTableView addTableColumn:runnerNameColumn];
	[resultsTableView addTableColumn:durationColumn];

	[self configureResultsTableViewDataSource];

	NSScrollView *scrollView = [[NSScrollView alloc] init];
	scrollView.documentView = resultsTableView;
	scrollView.hasVerticalScroller = YES;
	[stackView addArrangedSubview:scrollView];
}

- (void)configureResultsTableViewDataSource
{
	NSTableViewDiffableDataSourceCellProvider provider = ^(
	        NSTableView *_tableView, NSTableColumn *column, NSInteger row, id itemId) {
	  NSString *cellIdentifier = @"Cell";
	  NSTextField *view = [resultsTableView makeViewWithIdentifier:cellIdentifier owner:self];
	  if (view == nil)
	  {
		  view = [NSTextField labelWithString:@""];
		  view.identifier = cellIdentifier;
	  }

	  CellId *cellId = itemId;
	  if ([column.identifier isEqualToString:RunnerNameColumnIdentifier])
	  {
		  view.stringValue = cellId.benchmarkRunner;
	  }
	  else if ([column.identifier isEqualToString:DurationColumnIdentifier])
	  {
		  view.stringValue =
			  [NSString stringWithFormat:@"%.2f", cellId.averageDuration * 1000];
		  view.alignment = NSTextAlignmentRight;
		  view.font = EnableTabularNumbers(view.font);
	  }

	  return view;
	};

	dataSource = [[NSTableViewDiffableDataSource alloc] initWithTableView:resultsTableView
	                                                         cellProvider:provider];
}

- (void)didPressRunBenchmarks:(NSButton *)sender
{
	sender.enabled = NO;
	NSProgress *progress = [[NSProgress alloc] init];
	progressIndicator.observedProgress = progress;

	dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
	dispatch_async(queue, ^{
	  RunBenchmark(progress, dataSource);
	  dispatch_sync(dispatch_get_main_queue(), ^{
	    sender.enabled = YES;
	  });
	});
}

static void
RunBenchmark(NSProgress *progress, NSTableViewDiffableDataSource *dataSource)
{
	float scaleFactor = 2;
	uint64_t width = 5120;
	uint64_t height = 2880;
	MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	Renderer *renderer = [[Renderer alloc] initWithDevice:device
	                                          pixelFormat:MTLPixelFormatBGRA8Unorm];

	simd_float2 size = {(float)width / scaleFactor, (float)height / scaleFactor};
	[renderer setSize:size scaleFactor:scaleFactor];

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = width;
	descriptor.height = height;
	descriptor.pixelFormat = pixelFormat;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	descriptor.storageMode = MTLStorageModePrivate;
	id<MTLTexture> target = [device newTextureWithDescriptor:descriptor];

	double averageDuration = 0;
	uint64_t count = 1024;
	progress.totalUnitCount = (int64_t)count;

	for (uint64_t i = 0; i < count; i++)
	{
		id<MTLCommandBuffer> commandBuffer = [renderer render:target];
		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];
		progress.completedUnitCount++;

		double duration = commandBuffer.GPUEndTime - commandBuffer.GPUStartTime;
		averageDuration += duration;
	}

	averageDuration /= count;

	NSDiffableDataSourceSnapshot<NSNumber *, CellId *> *snapshot =
	        [[NSDiffableDataSourceSnapshot alloc] init];
	[snapshot appendSectionsWithIdentifiers:@[ @0 ]];

	CellId *cellId = [[CellId alloc] init];
	cellId.benchmarkRunner = @"Sample Every Pixel";
	cellId.averageDuration = averageDuration;
	[snapshot appendItemsWithIdentifiers:@[ cellId ]];

	dispatch_sync(dispatch_get_main_queue(), ^{
	  [dataSource applySnapshot:snapshot animatingDifferences:YES];
	});
}

static NSFont *
EnableTabularNumbers(NSFont *font)
{
	NSFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
		NSFontFeatureSettingsAttribute : @[
			@{
				NSFontFeatureTypeIdentifierKey : @(kNumberSpacingType),
				NSFontFeatureSelectorIdentifierKey : @(kMonospacedNumbersSelector)
			},
		]
	}];
	return [NSFont fontWithDescriptor:descriptor size:font.pointSize];
}

@end
