@interface BenchmarksViewController : NSViewController
{
	NSStackView *stackView;
	NSProgressIndicator *progressIndicator;
}
@end

@implementation BenchmarksViewController

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
}

- (void)didPressRunBenchmarks:(NSButton *)sender
{
	sender.enabled = NO;
	NSProgress *progress = [[NSProgress alloc] init];
	progressIndicator.observedProgress = progress;

	dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
	dispatch_async(queue, ^{
	  RunBenchmark(progress);
	  dispatch_sync(dispatch_get_main_queue(), ^{
	    sender.enabled = YES;
	  });
	});
}

static void
RunBenchmark(NSProgress *progress)
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

	printf("%.2f ms\n", averageDuration / count * 1000);
}

@end
