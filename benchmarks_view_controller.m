@interface BenchmarksViewController : NSViewController
@property NSStackView *stackView;
@property NSProgressIndicator *progressIndicator;
@property NSTableView *resultsTableView;
@property NSTableViewDiffableDataSource *dataSource;
@end

typedef struct BlurImplementationToDurationMap BlurImplementationToDurationMap;
struct BlurImplementationToDurationMap
{
	double durations[BlurImplementation__Count];
};

@interface CellId : NSObject
@property float blurRadius;
@property BlurImplementationToDurationMap durationsMap;
@end

@implementation CellId
@end

NSString *ResultsTableCellViewIdentifier = @"ResultsTableCellView";

@interface ResultsTableCellView : NSView
@property NSTextField *textField;
@end

@implementation ResultsTableCellView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	self.identifier = ResultsTableCellViewIdentifier;

	self.textField = [NSTextField labelWithString:@""];
	self.textField.alignment = NSTextAlignmentRight;
	self.textField.font = EnableTabularNumbers(self.textField.font);

	[self addSubview:self.textField];
	self.textField.translatesAutoresizingMaskIntoConstraints = NO;
	[NSLayoutConstraint activateConstraints:@[
		[self.textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[self.textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[self.textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
	]];

	return self;
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

@implementation BenchmarksViewController

NSString *BlurRadiusColumnIdentifier = @"BlurRadius";

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
	self.resultsTableView.allowsColumnResizing = NO;

	NSTableColumn *blurRadiusColumn =
	        [[NSTableColumn alloc] initWithIdentifier:BlurRadiusColumnIdentifier];
	blurRadiusColumn.title = @"Blur Radius";
	blurRadiusColumn.resizingMask = 0;
	[blurRadiusColumn sizeToFit];
	blurRadiusColumn.width += 50;
	[self.resultsTableView addTableColumn:blurRadiusColumn];

	for (BlurImplementation blurImplementation = 0;
	        blurImplementation < BlurImplementation__Count; blurImplementation++)
	{
		NSTableColumn *durationColumn = [[NSTableColumn alloc]
		        initWithIdentifier:[[NSString alloc] initWithFormat:@"Duration %d",
		                                             blurImplementation]];
		durationColumn.title = StringFromBlurImplementation(blurImplementation);
		durationColumn.resizingMask = 0;
		[durationColumn sizeToFit];
		durationColumn.width += 10;
		[self.resultsTableView addTableColumn:durationColumn];
	}

	[self configureResultsTableViewDataSource];

	NSScrollView *scrollView = [[NSScrollView alloc] init];
	scrollView.documentView = self.resultsTableView;
	scrollView.hasVerticalScroller = YES;
	scrollView.hasHorizontalScroller = YES;
	scrollView.autohidesScrollers = YES;
	[self.stackView addArrangedSubview:scrollView];
}

- (void)configureResultsTableViewDataSource
{
	NSTableViewDiffableDataSourceCellProvider provider = ^(
	        NSTableView *_tableView, NSTableColumn *column, NSInteger row, id itemId) {
	  ResultsTableCellView *view =
		  [self.resultsTableView makeViewWithIdentifier:ResultsTableCellViewIdentifier
		                                          owner:self];
	  if (view == nil)
	  {
		  view = [[ResultsTableCellView alloc] init];
	  }

	  CellId *cellId = itemId;
	  if ([column.identifier isEqualToString:BlurRadiusColumnIdentifier])
	  {
		  view.textField.stringValue =
			  [NSString stringWithFormat:@"%.02f", cellId.blurRadius];
	  }
	  else
	  {
		  NSArray<NSString *> *components =
			  [column.identifier componentsSeparatedByString:@" "];
		  BlurImplementation blurImplementation =
			  (BlurImplementation)components[1].intValue;
		  view.textField.stringValue =
			  [NSString stringWithFormat:@"%.2f",
			            cellId.durationsMap.durations[blurImplementation] * 1000];
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
	uint64_t width = 1600;
	uint64_t height = 900;
	simd_float2 size = {(float)width / scaleFactor, (float)height / scaleFactor};

	MTLPixelFormat pixelFormat = MTLPixelFormatRGBA16Float;

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = width;
	descriptor.height = height;
	descriptor.pixelFormat = pixelFormat;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead |
	                   MTLTextureUsageShaderWrite;
	descriptor.storageMode = MTLStorageModePrivate;
	id<MTLTexture> target = [device newTextureWithDescriptor:descriptor];

	uint64_t trialCount = 64;
	uint64_t blurRadiusCount = 26;
	progress.totalUnitCount =
	        (int64_t)(trialCount * blurRadiusCount * BlurImplementation__Count);

	NSDiffableDataSourceSnapshot<NSNumber *, CellId *> *snapshot =
	        [[NSDiffableDataSourceSnapshot alloc] init];
	[snapshot appendSectionsWithIdentifiers:@[ @0 ]];

	float blurRadiusMinimum = 0;
	float blurRadiusMaximum = 300;
	float blurRadiusStep = (blurRadiusMaximum - blurRadiusMinimum) / (blurRadiusCount - 1);

	NSMutableString *csv = [[NSMutableString alloc] init];

	[csv appendString:@"Blur Radius"];
	for (BlurImplementation blurImplementation = 0;
	        blurImplementation < BlurImplementation__Count; blurImplementation++)
	{
		[csv appendFormat:@",%@", StringFromBlurImplementation(blurImplementation)];
	}
	[csv appendString:@"\n"];

	Renderer *renderer = [[Renderer alloc] initWithDevice:device pixelFormat:pixelFormat];
	[renderer setSize:size scaleFactor:scaleFactor];

	for (float blurRadius = blurRadiusMinimum; blurRadius <= blurRadiusMaximum;
	        blurRadius += blurRadiusStep)
	{
		[csv appendFormat:@"%.02f,", blurRadius];

		BlurImplementationToDurationMap durationsMap = {0};

		for (BlurImplementation blurImplementation = 0;
		        blurImplementation < BlurImplementation__Count; blurImplementation++)
		{
			renderer.blurImplementation = blurImplementation;
			renderer.blurRadius = blurRadius;

			double averageDuration = 0;

			for (uint64_t i = 0; i < trialCount; i++)
			{
				id<MTLCommandBuffer> commandBuffer = [renderer render:target];
				[commandBuffer commit];
				[commandBuffer waitUntilCompleted];
				progress.completedUnitCount++;

				double duration =
				        commandBuffer.GPUEndTime - commandBuffer.GPUStartTime;
				averageDuration += duration;
			}

			averageDuration /= trialCount;
			durationsMap.durations[blurImplementation] = averageDuration;

			if (blurImplementation != 0)
			{
				[csv appendString:@","];
			}
			[csv appendFormat:@"%.02f", averageDuration * 1000];
		}

		[csv appendString:@"\n"];

		CellId *cellId = [[CellId alloc] init];
		cellId.blurRadius = blurRadius;
		cellId.durationsMap = durationsMap;
		[snapshot appendItemsWithIdentifiers:@[ cellId ]];

		dispatch_sync(dispatch_get_main_queue(), ^{
		  [dataSource applySnapshot:snapshot animatingDifferences:YES];
		});
	}

	NSString *documentsDirectory =
	        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];

	[csv writeToFile:[documentsDirectory stringByAppendingPathComponent:@"benchmark.csv"]
	        atomically:YES
	          encoding:NSUTF8StringEncoding
	             error:nil];
}

@end
