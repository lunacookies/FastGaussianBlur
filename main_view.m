@interface MainView : NSView
{
	CAMetalLayer *metalLayer;
	CADisplayLink *displayLink;
	Renderer *renderer;
}
@end

@implementation MainView

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
	if (scaleFactor == 0)
	{
		return;
	}

	NSSize size = self.frame.size;
	size.width *= scaleFactor;
	size.height *= scaleFactor;

	metalLayer.contentsScale = scaleFactor;
	metalLayer.drawableSize = size;

	[renderer setSize:(simd_float2){(float)self.frame.size.width, (float)self.frame.size.height}
	        scaleFactor:(float)scaleFactor];
}

@end
