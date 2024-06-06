@interface MainView : NSView
@end

@implementation MainView

id<MTLDevice> device;
CAMetalLayer *metalLayer;
id<MTLCommandQueue> commandQueue;
CADisplayLink *displayLink;
id<MTLRenderPipelineState> pipelineState;

uint64_t count;
simd_float2 size;
simd_float2 *positions;
simd_float3 *colors;

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	device = MTLCreateSystemDefaultDevice();
	metalLayer = (CAMetalLayer *)self.layer;
	metalLayer.device = device;

	commandQueue = [device newCommandQueue];

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *libraryURL = [bundle URLForResource:@"shaders" withExtension:@"metallib"];
	id<MTLLibrary> library = [device newLibraryWithURL:libraryURL error:nil];

	MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
	descriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat;
	descriptor.vertexFunction = [library newFunctionWithName:@"VertexFunction"];
	descriptor.fragmentFunction = [library newFunctionWithName:@"FragmentFunction"];
	pipelineState = [device newRenderPipelineStateWithDescriptor:descriptor error:nil];

	displayLink = [self displayLinkWithTarget:self selector:@selector(render)];
	[displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	uint64_t rows = 5;
	uint64_t columns = 10;
	count = rows * columns;

	size = (simd_float2){40, 40};
	simd_float2 padding = {30, 30};

	positions = calloc(count, sizeof(simd_float2));
	colors = calloc(count, sizeof(simd_float3));

	for (uint64_t y = 0; y < rows; y++)
	{
		for (uint64_t x = 0; x < columns; x++)
		{
			uint64_t i = y * columns + x;

			positions[i].x = x + 1;
			positions[i].y = y + 1;
			positions[i] *= size + padding;

			colors[i].r = (float)arc4random_uniform(255) / 255;
			colors[i].g = (float)arc4random_uniform(255) / 255;
			colors[i].b = (float)arc4random_uniform(255) / 255;
		}
	}

	return self;
}

- (void)render
{
	id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];

	id<CAMetalDrawable> drawable = [metalLayer nextDrawable];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = drawable.texture;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

	simd_float2 resolution = 0;
	resolution.x = (float)self.frame.size.width;
	resolution.y = (float)self.frame.size.height;

	[encoder setRenderPipelineState:pipelineState];

	[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:0];
	[encoder setVertexBytes:positions length:sizeof(simd_float2) * count atIndex:1];
	[encoder setVertexBytes:colors length:sizeof(simd_float3) * count atIndex:2];
	[encoder setVertexBytes:&size length:sizeof(size) atIndex:3];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:count];

	[encoder endEncoding];

	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	metalLayer.contentsScale = self.window.backingScaleFactor;
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];

	float scaleFactor = (float)self.window.backingScaleFactor;
	if (scaleFactor == 0)
	{
		return;
	}
	size.width *= scaleFactor;
	size.height *= scaleFactor;
	metalLayer.drawableSize = size;
}

@end
