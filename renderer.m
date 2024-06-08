@interface Renderer : NSObject
{
	id<MTLDevice> device;
	id<MTLCommandQueue> commandQueue;

	simd_float2 size;
	float scaleFactor;
	MTLPixelFormat pixelFormat;
	id<MTLTexture> offscreenTexture;

	id<MTLRenderPipelineState> pipelineState;
	id<MTLRenderPipelineState> pipelineStateBlur;

	uint64_t boxCount;
	simd_float2 *boxPositions;
	simd_float2 *boxSizes;
	simd_float4 *boxColors;

	float blurRadius;
}
@end

@implementation Renderer

- (instancetype)initWithDevice:(id<MTLDevice>)_device pixelFormat:(MTLPixelFormat)_pixelFormat
{
	self = [super init];

	device = _device;
	pixelFormat = _pixelFormat;
	commandQueue = [device newCommandQueue];

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *libraryURL = [bundle URLForResource:@"shaders" withExtension:@"metallib"];
	id<MTLLibrary> library = [device newLibraryWithURL:libraryURL error:nil];

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = pixelFormat;
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
		descriptor.colorAttachments[0].pixelFormat = pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertexFunction"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"BlurFragmentFunction"];
		pipelineStateBlur = [device newRenderPipelineStateWithDescriptor:descriptor
		                                                           error:nil];
	}

	uint64_t rows = 5;
	uint64_t columns = 10;
	boxCount = rows * columns;

	simd_float2 boxSize = {40, 40};
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
			boxPositions[i] *= boxSize + padding;

			boxSizes[i] = boxSize;

			boxColors[i].r = (float)arc4random_uniform(255) / 255;
			boxColors[i].g = (float)arc4random_uniform(255) / 255;
			boxColors[i].b = (float)arc4random_uniform(255) / 255;
			boxColors[i].a = 1;
		}
	}

	return self;
}

- (id<MTLCommandBuffer>)render:(id<MTLTexture>)target
{
	id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = target;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

	[self drawBoxesWithEncoder:encoder
	                    target:target
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
		float blurRadii[] = {blurRadius, blurRadius, blurRadius};

		[encoder endEncoding];
		encoder = [self blurWithCommandBuffer:commandBuffer
		                               target:target
		                            positions:positions
		                                sizes:sizes
		                            blurRadii:blurRadii
		                                count:3];

		[self drawBoxesWithEncoder:encoder
		                    target:target
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
		float blurRadii[] = {
		        blurRadius,
		};

		[encoder endEncoding];
		encoder = [self blurWithCommandBuffer:commandBuffer
		                               target:target
		                            positions:positions
		                                sizes:sizes
		                            blurRadii:blurRadii
		                                count:1];

		[self drawBoxesWithEncoder:encoder
		                    target:target
		                 positions:positions
		                     sizes:sizes
		                    colors:colors
		                     count:1];
	}

	[encoder endEncoding];

	return commandBuffer;
}

- (void)drawBoxesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                      target:(id<MTLTexture>)target
                   positions:(simd_float2 *)positions
                       sizes:(simd_float2 *)sizes
                      colors:(simd_float4 *)colors
                       count:(uint64_t)count
{
	simd_float2 resolution = size * scaleFactor;

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
                                           blurRadii:(float *)blurRadii
                                               count:(uint64_t)count
{
	{
		MTLBlitPassDescriptor *descriptor = [[MTLBlitPassDescriptor alloc] init];
		id<MTLBlitCommandEncoder> encoder =
		        [commandBuffer blitCommandEncoderWithDescriptor:descriptor];
		[encoder copyFromTexture:target toTexture:offscreenTexture];
		[encoder endEncoding];
	}

	simd_float2 resolution = size * scaleFactor;

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
		[encoder setFragmentBytes:&scaleFactor length:sizeof(scaleFactor) atIndex:1];
		[encoder setFragmentBytes:&horizontal length:sizeof(horizontal) atIndex:2];
		[encoder setFragmentBytes:blurRadii length:sizeof(float) * count atIndex:3];

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

- (void)setSize:(simd_float2)_size scaleFactor:(float)_scaleFactor
{
	size = _size;
	scaleFactor = _scaleFactor;

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = (NSUInteger)(size.x * scaleFactor);
	descriptor.height = (NSUInteger)(size.y * scaleFactor);
	descriptor.pixelFormat = pixelFormat;
	descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
	descriptor.storageMode = MTLStorageModePrivate;

	offscreenTexture = [device newTextureWithDescriptor:descriptor];
	offscreenTexture.label = @"Offscreen Texture";
}

- (void)setBlurRadius:(float)_blurRadius
{
	blurRadius = _blurRadius;
}

@end
