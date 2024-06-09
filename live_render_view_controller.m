@interface LiveRenderView : NSView
{
	BlurImplementation _blurImplementation;
}

@property id<MTLDevice> device;
@property CAMetalLayer *metalLayer;
@property CADisplayLink *displayLink;
@property Renderer *renderer;
@property(getter=blurImplementation, setter=setBlurImplementation:)
        BlurImplementation blurImplementation;

@end

@implementation LiveRenderView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	self.device = MTLCreateSystemDefaultDevice();

	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	self.metalLayer = (CAMetalLayer *)self.layer;
	self.metalLayer.device = self.device;
	self.metalLayer.framebufferOnly = NO;

	self.displayLink = [self displayLinkWithTarget:self selector:@selector(render)];
	[self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	return self;
}

- (void)render
{
	id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
	id<MTLCommandBuffer> commandBuffer = [self.renderer render:drawable.texture];
	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
}

- (BlurImplementation)blurImplementation
{
	return _blurImplementation;
}

- (void)setBlurImplementation:(BlurImplementation)blurImplementation
{
	_blurImplementation = blurImplementation;
	self.renderer = [[Renderer alloc] initWithDevice:self.device
	                                     pixelFormat:self.metalLayer.pixelFormat
	                              blurImplementation:self.blurImplementation];
	[self updateTextures];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	[self updateTextures];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self updateTextures];
}

- (void)updateTextures
{
	double scaleFactor = self.window.backingScaleFactor;
	NSSize size = self.frame.size;
	size.width *= scaleFactor;
	size.height *= scaleFactor;

	if (size.width == 0 || size.height == 0)
	{
		return;
	}

	self.metalLayer.contentsScale = scaleFactor;
	self.metalLayer.drawableSize = size;

	[self.renderer setSize:(simd_float2){
	                               (float)self.frame.size.width, (float)self.frame.size.height}
	           scaleFactor:(float)scaleFactor];
}

@end

@interface LiveRenderViewController : NSViewController
@property LiveRenderView *liveRenderView;
@property NSStackView *inspector;
@property NSButton *sampleEveryPixelRadioButton;
@property NSTextField *blurRadiusLabel;
@property NSSlider *blurRadiusSlider;
@end

@implementation LiveRenderViewController

- (instancetype)init
{
	self = [super init];
	self.title = @"Live Rendered View";
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.liveRenderView = [[LiveRenderView alloc] init];

	self.inspector = [[NSStackView alloc] init];
	self.inspector.orientation = NSUserInterfaceLayoutOrientationVertical;
	self.inspector.alignment = NSLayoutAttributeLeading;

	NSTextField *titleLabel = [NSTextField labelWithString:@"Inspector"];
	titleLabel.font = [NSFont boldSystemFontOfSize:16];
	[self.inspector addArrangedSubview:titleLabel];

	NSTextField *implementationLabel = [NSTextField labelWithString:@"Blur Implementation:"];
	[self.inspector addArrangedSubview:implementationLabel];

	self.sampleEveryPixelRadioButton =
	        [NSButton radioButtonWithTitle:@"Sample Every Pixel"
	                                target:self
	                                action:@selector(updateConfiguration:)];
	[self.inspector addArrangedSubview:self.sampleEveryPixelRadioButton];

	self.blurRadiusLabel = [NSTextField labelWithString:@""];
	[self.inspector addArrangedSubview:self.blurRadiusLabel];

	self.blurRadiusSlider = [NSSlider sliderWithValue:50
	                                         minValue:FLT_EPSILON
	                                         maxValue:150
	                                           target:self
	                                           action:@selector(updateConfiguration:)];
	[self.inspector addArrangedSubview:self.blurRadiusSlider];

	[self updateConfiguration:nil];

	[self.view addSubview:self.liveRenderView];
	[self.view addSubview:self.inspector];
	self.liveRenderView.translatesAutoresizingMaskIntoConstraints = NO;
	self.inspector.translatesAutoresizingMaskIntoConstraints = NO;

	CGFloat padding = 24;
	[NSLayoutConstraint activateConstraints:@[
		[self.liveRenderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.liveRenderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.liveRenderView.trailingAnchor
		        constraintEqualToAnchor:self.inspector.leadingAnchor
		                       constant:-padding],
		[self.liveRenderView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.inspector.topAnchor constraintEqualToAnchor:self.view.topAnchor
		                                         constant:padding],
		[self.inspector.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
		                                              constant:-padding],
		[self.inspector.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
		                                            constant:-padding],

		[titleLabel.bottomAnchor constraintEqualToAnchor:implementationLabel.topAnchor
		                                        constant:-24],
		[self.blurRadiusSlider.widthAnchor constraintGreaterThanOrEqualToConstant:150],
	]];
}

- (void)updateConfiguration:(id)sender
{
	if (sender == self.sampleEveryPixelRadioButton)
	{
		self.liveRenderView.blurImplementation = BlurImplementation_SampleEveryPixel;
	}

	self.blurRadiusLabel.stringValue =
	        [NSString stringWithFormat:@"Blur Radius: %.02f", self.blurRadiusSlider.floatValue];
	self.liveRenderView.renderer.blurRadius = self.blurRadiusSlider.floatValue;
}

@end
