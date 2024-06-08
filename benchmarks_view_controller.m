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
@property float blurRadius;
@property double averageDuration;
@end

@implementation CellId
@end

@implementation BenchmarksViewController

NSString *RunnerNameColumnIdentifier = @"RunnerName";
NSString *BlurRadiusColumnIdentifier = @"BlurRadius";
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
	NSTableColumn *blurRadiusColumn =
	        [[NSTableColumn alloc] initWithIdentifier:BlurRadiusColumnIdentifier];
	NSTableColumn *durationColumn =
	        [[NSTableColumn alloc] initWithIdentifier:DurationColumnIdentifier];

	runnerNameColumn.title = @"Benchmark Runner";
	blurRadiusColumn.title = @"Blur Radius";
	durationColumn.title = @"Duration (ms)";

	runnerNameColumn.width = 160;
	blurRadiusColumn.width = 80;
	durationColumn.width = 80;

	runnerNameColumn.resizingMask = 0;
	blurRadiusColumn.resizingMask = 0;
	durationColumn.resizingMask = 0;

	[resultsTableView addTableColumn:runnerNameColumn];
	[resultsTableView addTableColumn:blurRadiusColumn];
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
	  else if ([column.identifier isEqualToString:BlurRadiusColumnIdentifier])
	  {
		  view.stringValue = [NSString stringWithFormat:@"%.02f", cellId.blurRadius];
		  view.alignment = NSTextAlignmentRight;
		  view.font = EnableTabularNumbers(view.font);
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
	simd_float2 size = {(float)width / scaleFactor, (float)height / scaleFactor};

	MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = width;
	descriptor.height = height;
	descriptor.pixelFormat = pixelFormat;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	descriptor.storageMode = MTLStorageModePrivate;
	id<MTLTexture> target = [device newTextureWithDescriptor:descriptor];

	uint64_t trialCount = 64;
	uint64_t blurRadiusCount = 26;
	progress.totalUnitCount = (int64_t)(trialCount * blurRadiusCount);

	NSDiffableDataSourceSnapshot<NSNumber *, CellId *> *snapshot =
	        [[NSDiffableDataSourceSnapshot alloc] init];
	[snapshot appendSectionsWithIdentifiers:@[ @0 ]];

	float blurRadiusMinimum = 0;
	float blurRadiusMaximum = 300;
	float blurRadiusStep = (blurRadiusMaximum - blurRadiusMinimum) / (blurRadiusCount - 1);

	for (float blurRadius = blurRadiusMinimum; blurRadius <= blurRadiusMaximum;
	        blurRadius += blurRadiusStep)
	{
		Renderer *renderer = [[Renderer alloc] initWithDevice:device
		                                          pixelFormat:MTLPixelFormatBGRA8Unorm
		                                           blurRadius:blurRadius];

		[renderer setSize:size scaleFactor:scaleFactor];

		double averageDuration = 0;

		for (uint64_t i = 0; i < trialCount; i++)
		{
			id<MTLCommandBuffer> commandBuffer = [renderer render:target];
			[commandBuffer commit];
			[commandBuffer waitUntilCompleted];
			progress.completedUnitCount++;

			double duration = commandBuffer.GPUEndTime - commandBuffer.GPUStartTime;
			averageDuration += duration;
		}

		averageDuration /= trialCount;

		CellId *cellId = [[CellId alloc] init];
		cellId.benchmarkRunner = @"Sample Every Pixel";
		cellId.blurRadius = blurRadius;
		cellId.averageDuration = averageDuration;
		[snapshot appendItemsWithIdentifiers:@[ cellId ]];

		dispatch_sync(dispatch_get_main_queue(), ^{
		  [dataSource applySnapshot:snapshot animatingDifferences:YES];
		});
	}
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
