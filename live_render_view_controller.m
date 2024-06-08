@interface LiveRenderView : NSView
{
	CAMetalLayer *metalLayer;
	CADisplayLink *displayLink;
	Renderer *renderer;
}
@end

@implementation LiveRenderView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();

	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	metalLayer = (CAMetalLayer *)self.layer;
	metalLayer.device = device;
	metalLayer.framebufferOnly = NO;

	renderer = [[Renderer alloc] initWithDevice:device pixelFormat:metalLayer.pixelFormat];

	displayLink = [self displayLinkWithTarget:self selector:@selector(render)];
	[displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	return self;
}

- (void)render
{
	id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
	id<MTLCommandBuffer> commandBuffer = [renderer render:drawable.texture];
	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
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

	metalLayer.contentsScale = scaleFactor;
	metalLayer.drawableSize = size;

	[renderer setSize:(simd_float2){(float)self.frame.size.width, (float)self.frame.size.height}
	        scaleFactor:(float)scaleFactor];
}

- (void)setBlurRadius:(float)blurRadius
{
	[renderer setBlurRadius:blurRadius];
}

@end

@interface LiveRenderViewController : NSViewController
{
	LiveRenderView *liveRenderView;
	NSStackView *inspector;
	NSTextField *blurRadiusLabel;
	NSSlider *blurRadiusSlider;
}
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

	liveRenderView = [[LiveRenderView alloc] init];

	inspector = [[NSStackView alloc] init];
	inspector.orientation = NSUserInterfaceLayoutOrientationVertical;
	inspector.alignment = NSLayoutAttributeLeading;

	NSTextField *titleLabel = [NSTextField labelWithString:@"Inspector"];
	titleLabel.font = [NSFont boldSystemFontOfSize:16];
	[inspector addArrangedSubview:titleLabel];

	blurRadiusLabel = [NSTextField labelWithString:@""];
	[inspector addArrangedSubview:blurRadiusLabel];

	blurRadiusSlider = [NSSlider sliderWithValue:50
	                                    minValue:FLT_EPSILON
	                                    maxValue:150
	                                      target:self
	                                      action:@selector(updateConfiguration:)];
	[inspector addArrangedSubview:blurRadiusSlider];

	[self updateConfiguration:nil];

	[self.view addSubview:liveRenderView];
	[self.view addSubview:inspector];
	liveRenderView.translatesAutoresizingMaskIntoConstraints = NO;
	inspector.translatesAutoresizingMaskIntoConstraints = NO;

	CGFloat padding = 24;
	[NSLayoutConstraint activateConstraints:@[
		[liveRenderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[liveRenderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[liveRenderView.trailingAnchor constraintEqualToAnchor:inspector.leadingAnchor
		                                              constant:-padding],
		[liveRenderView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[inspector.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:padding],
		[inspector.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
		                                         constant:-padding],
		[inspector.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
		                                       constant:-padding],

		[titleLabel.bottomAnchor constraintEqualToAnchor:blurRadiusLabel.topAnchor
		                                        constant:-24],
		[blurRadiusSlider.widthAnchor constraintGreaterThanOrEqualToConstant:150],
	]];
}

- (void)updateConfiguration:(id)sender
{
	blurRadiusLabel.stringValue =
	        [NSString stringWithFormat:@"Blur Radius: %.02f", blurRadiusSlider.floatValue];
	[liveRenderView setBlurRadius:blurRadiusSlider.floatValue];
}

@end
