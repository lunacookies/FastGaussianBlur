@interface BenchmarksViewController : NSViewController
@property NSStackView *stackView;
@property NSProgressIndicator *progressIndicator;
@property NSTableView *resultsTableView;
@property NSTableViewDiffableDataSource *dataSource;
@end

@interface CellId : NSObject
@property BlurImplementation blurImplementation;
@property float blurRadius;
@property double averageDuration;
@end

@implementation CellId
@end

@implementation BenchmarksViewController

NSString *BlurImplementationColumnIdentifier = @"BlurImplementation";
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
	self.stackView = [[NSStackView alloc] init];
	self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
	self.stackView.alignment = NSLayoutAttributeLeading;

	[self.view addSubview:self.stackView];
	self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
	[NSLayoutConstraint activateConstraints:@[
		[self.stackView.topAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.topAnchor],
		[self.stackView.leadingAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
		[self.stackView.trailingAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
		[self.stackView.bottomAnchor
		        constraintEqualToAnchor:self.view.layoutMarginsGuide.bottomAnchor],
	]];

	NSButton *runBenchmarkButton = [NSButton buttonWithTitle:@"Run Benchmark"
	                                                  target:self
	                                                  action:@selector(didPressRunBenchmarks:)];
	[self.stackView addArrangedSubview:runBenchmarkButton];

	self.progressIndicator = [[NSProgressIndicator alloc] init];
	[self.stackView addArrangedSubview:self.progressIndicator];

	[self configureResultsTable];
}

- (void)configureResultsTable
{
	self.resultsTableView = [[NSTableView alloc] init];
	self.resultsTableView.allowsColumnReordering = NO;

	NSTableColumn *blurImplementationColumn =
	        [[NSTableColumn alloc] initWithIdentifier:BlurImplementationColumnIdentifier];
	NSTableColumn *blurRadiusColumn =
	        [[NSTableColumn alloc] initWithIdentifier:BlurRadiusColumnIdentifier];
	NSTableColumn *durationColumn =
	        [[NSTableColumn alloc] initWithIdentifier:DurationColumnIdentifier];

	blurImplementationColumn.title = @"Blur Implementation";
	blurRadiusColumn.title = @"Blur Radius";
	durationColumn.title = @"Duration (ms)";

	blurImplementationColumn.width = 160;
	blurRadiusColumn.width = 80;
	durationColumn.width = 80;

	blurImplementationColumn.resizingMask = 0;
	blurRadiusColumn.resizingMask = 0;
	durationColumn.resizingMask = 0;

	[self.resultsTableView addTableColumn:blurImplementationColumn];
	[self.resultsTableView addTableColumn:blurRadiusColumn];
	[self.resultsTableView addTableColumn:durationColumn];

	[self configureResultsTableViewDataSource];

	NSScrollView *scrollView = [[NSScrollView alloc] init];
	scrollView.documentView = self.resultsTableView;
	scrollView.hasVerticalScroller = YES;
	[self.stackView addArrangedSubview:scrollView];
}

- (void)configureResultsTableViewDataSource
{
	NSTableViewDiffableDataSourceCellProvider provider = ^(
	        NSTableView *_tableView, NSTableColumn *column, NSInteger row, id itemId) {
	  NSString *cellIdentifier = @"Cell";
	  NSTextField *view = [self.resultsTableView makeViewWithIdentifier:cellIdentifier
		                                                      owner:self];
	  if (view == nil)
	  {
		  view = [NSTextField labelWithString:@""];
		  view.identifier = cellIdentifier;
	  }

	  CellId *cellId = itemId;
	  if ([column.identifier isEqualToString:BlurImplementationColumnIdentifier])
	  {
		  switch (cellId.blurImplementation)
		  {
			  case BlurImplementation_SampleEveryPixel:
				  view.stringValue = @"Sample Every Pixel";
				  break;
		  }
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

	self.dataSource =
	        [[NSTableViewDiffableDataSource alloc] initWithTableView:self.resultsTableView
	                                                    cellProvider:provider];
}

- (void)didPressRunBenchmarks:(NSButton *)sender
{
	sender.enabled = NO;
	NSProgress *progress = [[NSProgress alloc] init];
	self.progressIndicator.observedProgress = progress;

	dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
	dispatch_async(queue, ^{
	  RunBenchmark(progress, self.dataSource);
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
		BlurImplementation blurImplementation = BlurImplementation_SampleEveryPixel;

		Renderer *renderer = [[Renderer alloc] initWithDevice:device
		                                          pixelFormat:MTLPixelFormatBGRA8Unorm
		                                   blurImplementation:blurImplementation];

		[renderer setSize:size scaleFactor:scaleFactor];
		renderer.blurRadius = blurRadius;

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
		cellId.blurImplementation = blurImplementation;
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
