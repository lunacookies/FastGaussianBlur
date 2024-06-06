@interface MainView : NSView
@end

@implementation MainView

id<MTLDevice> device;
CAMetalLayer *metalLayer;
id<MTLCommandQueue> commandQueue;
CADisplayLink *displayLink;

id<MTLTexture> offscreenTexture;

id<MTLRenderPipelineState> pipelineState;
id<MTLRenderPipelineState> pipelineStateBlur;

uint64_t boxCount;
simd_float2 *boxPositions;
simd_float2 *boxSizes;
simd_float4 *boxColors;

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	device = MTLCreateSystemDefaultDevice();
	metalLayer = (CAMetalLayer *)self.layer;
	metalLayer.device = device;
	metalLayer.framebufferOnly = NO;

	commandQueue = [device newCommandQueue];

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *libraryURL = [bundle URLForResource:@"shaders" withExtension:@"metallib"];
	id<MTLLibrary> library = [device newLibraryWithURL:libraryURL error:nil];

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat;
		descriptor.colorAttachments[0].blendingEnabled = YES;
		descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
		descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
		descriptor.colorAttachments[0].destinationRGBBlendFactor =
		        MTLBlendFactorOneMinusSourceAlpha;
		descriptor.colorAttachments[0].destinationAlphaBlendFactor =
		        MTLBlendFactorOneMinusSourceAlpha;
		descriptor.vertexFunction = [library newFunctionWithName:@"VertexFunction"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"FragmentFunction"];
		pipelineState = [device newRenderPipelineStateWithDescriptor:descriptor error:nil];
	}

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertexFunction"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"BlurFragmentFunction"];
		pipelineStateBlur = [device newRenderPipelineStateWithDescriptor:descriptor
		                                                           error:nil];
	}

	displayLink = [self displayLinkWithTarget:self selector:@selector(render)];
	[displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	uint64_t rows = 5;
	uint64_t columns = 10;
	boxCount = rows * columns;

	simd_float2 size = {40, 40};
	simd_float2 padding = {30, 30};

	boxPositions = calloc(boxCount, sizeof(simd_float2));
	boxSizes = calloc(boxCount, sizeof(simd_float2));
	boxColors = calloc(boxCount, sizeof(simd_float4));

	for (uint64_t y = 0; y < rows; y++)
	{
		for (uint64_t x = 0; x < columns; x++)
		{
			uint64_t i = y * columns + x;

			boxPositions[i].x = x + 1;
			boxPositions[i].y = y + 1;
			boxPositions[i] *= size + padding;

			boxSizes[i] = size;

			boxColors[i].r = (float)arc4random_uniform(255) / 255;
			boxColors[i].g = (float)arc4random_uniform(255) / 255;
			boxColors[i].b = (float)arc4random_uniform(255) / 255;
			boxColors[i].a = 1;
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

	[self drawBoxesWithEncoder:encoder
	                    target:drawable.texture
	                 positions:boxPositions
	                     sizes:boxSizes
	                    colors:boxColors
	                     count:boxCount];

	{
		simd_float2 positions[] = {
		        {100, 80},
		        {550, 50},
		        {50, 210},
		};
		simd_float2 sizes[] = {
		        {200, 100},
		        {150, 300},
		        {400, 150},
		};
		simd_float4 colors[] = {
		        {1, 1, 1, 0.25},
		        {1, 1, 1, 0.25},
		        {1, 1, 1, 0.25},
		};

		[encoder endEncoding];
		encoder = [self blurWithCommandBuffer:commandBuffer
		                               target:drawable.texture
		                            positions:positions
		                                sizes:sizes
		                                count:3];

		[self drawBoxesWithEncoder:encoder
		                    target:drawable.texture
		                 positions:positions
		                     sizes:sizes
		                    colors:colors
		                     count:3];
	}

	{
		simd_float2 positions[] = {
		        {200, 150},
		};
		simd_float2 sizes[] = {
		        {400, 180},
		};
		simd_float4 colors[] = {
		        {1, 1, 1, 0.25},
		};

		[encoder endEncoding];
		encoder = [self blurWithCommandBuffer:commandBuffer
		                               target:drawable.texture
		                            positions:positions
		                                sizes:sizes
		                                count:1];

		[self drawBoxesWithEncoder:encoder
		                    target:drawable.texture
		                 positions:positions
		                     sizes:sizes
		                    colors:colors
		                     count:1];
	}

	[encoder endEncoding];

	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
}

- (void)drawBoxesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                      target:(id<MTLTexture>)target
                   positions:(simd_float2 *)positions
                       sizes:(simd_float2 *)sizes
                      colors:(simd_float4 *)colors
                       count:(uint64_t)count
{
	float scaleFactor = (float)self.window.backingScaleFactor;

	simd_float2 resolution = 0;
	resolution.x = (float)self.frame.size.width;
	resolution.y = (float)self.frame.size.height;
	resolution *= scaleFactor;

	[encoder setRenderPipelineState:pipelineState];

	[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:0];
	[encoder setVertexBytes:&scaleFactor length:sizeof(scaleFactor) atIndex:1];
	[encoder setVertexBytes:positions length:sizeof(simd_float2) * count atIndex:2];
	[encoder setVertexBytes:sizes length:sizeof(simd_float2) * count atIndex:3];
	[encoder setVertexBytes:colors length:sizeof(simd_float4) * count atIndex:4];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:count];
}

- (id<MTLRenderCommandEncoder>)blurWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                              target:(id<MTLTexture>)target
                                           positions:(simd_float2 *)positions
                                               sizes:(simd_float2 *)sizes
                                               count:(uint64_t)count
{
	{
		MTLBlitPassDescriptor *descriptor = [[MTLBlitPassDescriptor alloc] init];
		id<MTLBlitCommandEncoder> encoder =
		        [commandBuffer blitCommandEncoderWithDescriptor:descriptor];
		[encoder copyFromTexture:target toTexture:offscreenTexture];
		[encoder endEncoding];
	}

	float scaleFactor = (float)self.window.backingScaleFactor;

	simd_float2 resolution = 0;
	resolution.x = (float)self.frame.size.width;
	resolution.y = (float)self.frame.size.height;
	resolution *= scaleFactor;

	id<MTLRenderCommandEncoder> encoder = nil;

	for (uint32_t horizontal = 0; horizontal <= 1; horizontal++)
	{
		MTLRenderPassDescriptor *descriptor =
		        [MTLRenderPassDescriptor renderPassDescriptor];

		if (horizontal)
		{
			descriptor.colorAttachments[0].texture = target;
		}
		else
		{
			descriptor.colorAttachments[0].texture = offscreenTexture;
		}

		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;

		encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

		[encoder setRenderPipelineState:pipelineStateBlur];

		[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:0];
		[encoder setVertexBytes:&scaleFactor length:sizeof(scaleFactor) atIndex:1];
		[encoder setVertexBytes:positions length:sizeof(simd_float2) * count atIndex:2];
		[encoder setVertexBytes:sizes length:sizeof(simd_float2) * count atIndex:3];
		[encoder setFragmentBytes:&resolution length:sizeof(resolution) atIndex:0];
		[encoder setFragmentBytes:&horizontal length:sizeof(horizontal) atIndex:1];

		if (horizontal)
		{
			[encoder setFragmentTexture:offscreenTexture atIndex:0];
		}
		else
		{
			[encoder setFragmentTexture:target atIndex:0];
		}

		[encoder drawPrimitives:MTLPrimitiveTypeTriangle
		            vertexStart:0
		            vertexCount:6
		          instanceCount:count];

		if (!horizontal)
		{
			[encoder endEncoding];
		}
	}

	return encoder;
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	metalLayer.contentsScale = self.window.backingScaleFactor;
	[self updateOffscreenTexture];
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
	[self updateOffscreenTexture];
}

- (void)updateOffscreenTexture
{
	float scaleFactor = (float)self.window.backingScaleFactor;
	NSSize size = self.frame.size;
	size.width *= scaleFactor;
	size.height *= scaleFactor;

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = (NSUInteger)size.width;
	descriptor.height = (NSUInteger)size.height;
	descriptor.pixelFormat = metalLayer.pixelFormat;
	descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
	descriptor.storageMode = MTLStorageModePrivate;

	offscreenTexture = [device newTextureWithDescriptor:descriptor];
	offscreenTexture.label = @"Offscreen Texture";
}

@end
