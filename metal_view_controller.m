@interface MetalViewController : NSViewController
{
	CAMetalLayer *metalLayer;
	CADisplayLink *displayLink;
	Renderer *renderer;
}
@end

@implementation MetalViewController

- (instancetype)init
{
	self = [super init];
	self.title = @"Live Rendered View";
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();

	self.view.wantsLayer = YES;
	self.view.layer = [CAMetalLayer layer];
	metalLayer = (CAMetalLayer *)self.view.layer;
	metalLayer.device = device;
	metalLayer.framebufferOnly = NO;

	renderer = [[Renderer alloc] initWithDevice:device
	                                pixelFormat:metalLayer.pixelFormat
	                                 blurRadius:100];

	displayLink = [self.view displayLinkWithTarget:self selector:@selector(render)];
	[displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)render
{
	id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
	id<MTLCommandBuffer> commandBuffer = [renderer render:drawable.texture];
	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
}

- (void)viewWillLayout
{
	[super viewWillLayout];

	double scaleFactor = self.view.window.backingScaleFactor;
	if (scaleFactor == 0)
	{
		return;
	}

	NSSize size = self.view.frame.size;
	size.width *= scaleFactor;
	size.height *= scaleFactor;

	metalLayer.contentsScale = scaleFactor;
	metalLayer.drawableSize = size;

	[renderer setSize:(simd_float2){(float)self.view.frame.size.width,
	                          (float)self.view.frame.size.height}
	        scaleFactor:(float)scaleFactor];
}

@end
