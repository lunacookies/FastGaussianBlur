typedef enum
{
	BlurImplementation_SampleEveryPixel,
	BlurImplementation_SamplePixelQuads,
	BlurImplementation__Count,
} BlurImplementation;

static char *BlurImplementationNames[] = {
        "Sample Every Pixel",
        "Sample Pixel Quads",
};

@interface Renderer : NSObject

@property id<MTLDevice> device;
@property id<MTLCommandQueue> commandQueue;

@property simd_float2 size;
@property float scaleFactor;
@property MTLPixelFormat pixelFormat;
@property id<MTLTexture> offscreenTexture;

@property id<MTLRenderPipelineState> pipelineState;
@property id<MTLRenderPipelineState> pipelineStateBlurSampleEveryPixel;
@property id<MTLRenderPipelineState> pipelineStateBlurSamplePixelQuads;

@property uint64_t boxCount;
@property simd_float2 *boxPositions;
@property simd_float2 *boxSizes;
@property simd_float4 *boxColors;

@property BlurImplementation blurImplementation;
@property float blurRadius;

@end

typedef struct Rng Rng;
struct Rng
{
	uint32_t state;
};

static Rng
RngCreate(void)
{
	Rng result = {0};
	result.state = 4; // chosen by fair dice roll, guaranteed to be random.
	return result;
}

static float
RngNextFloat(Rng *rng)
{
	uint32_t x = rng->state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	rng->state = x;
	return (float)x / (float)UINT32_MAX;
}

@implementation Renderer

- (instancetype)initWithDevice:(id<MTLDevice>)device pixelFormat:(MTLPixelFormat)pixelFormat
{
	self = [super init];

	self.device = device;
	self.pixelFormat = pixelFormat;
	self.commandQueue = [self.device newCommandQueue];

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *libraryURL = [bundle URLForResource:@"shaders" withExtension:@"metallib"];
	id<MTLLibrary> library = [self.device newLibraryWithURL:libraryURL error:nil];

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
		descriptor.colorAttachments[0].blendingEnabled = YES;
		descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
		descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
		descriptor.colorAttachments[0].destinationRGBBlendFactor =
		        MTLBlendFactorOneMinusSourceAlpha;
		descriptor.colorAttachments[0].destinationAlphaBlendFactor =
		        MTLBlendFactorOneMinusSourceAlpha;
		descriptor.vertexFunction = [library newFunctionWithName:@"VertexFunction"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"FragmentFunction"];
		self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor
		                                                                 error:nil];
	}

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertexFunction"];
		descriptor.fragmentFunction =
		        [library newFunctionWithName:@"BlurFragmentFunctionSampleEveryPixel"];
		self.pipelineStateBlurSampleEveryPixel =
		        [self.device newRenderPipelineStateWithDescriptor:descriptor error:nil];
	}

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertexFunction"];
		descriptor.fragmentFunction =
		        [library newFunctionWithName:@"BlurFragmentFunctionSamplePixelQuads"];
		self.pipelineStateBlurSamplePixelQuads =
		        [self.device newRenderPipelineStateWithDescriptor:descriptor error:nil];
	}

	uint64_t rows = 5;
	uint64_t columns = 10;
	self.boxCount = rows * columns;

	simd_float2 boxSize = {40, 40};
	simd_float2 padding = {30, 30};

	self.boxPositions = calloc(self.boxCount, sizeof(simd_float2));
	self.boxSizes = calloc(self.boxCount, sizeof(simd_float2));
	self.boxColors = calloc(self.boxCount, sizeof(simd_float4));

	Rng rng = RngCreate();

	for (uint64_t y = 0; y < rows; y++)
	{
		for (uint64_t x = 0; x < columns; x++)
		{
			uint64_t i = y * columns + x;

			self.boxPositions[i].x = x + 1;
			self.boxPositions[i].y = y + 1;
			self.boxPositions[i] *= boxSize + padding;

			self.boxSizes[i] = boxSize;

			self.boxColors[i].r = RngNextFloat(&rng);
			self.boxColors[i].g = RngNextFloat(&rng);
			self.boxColors[i].b = RngNextFloat(&rng);
			self.boxColors[i].a = 1;
		}
	}

	return self;
}

- (id<MTLCommandBuffer>)render:(id<MTLTexture>)target
{
	id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = target;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

	[self drawBoxesWithEncoder:encoder
	                    target:target
	                 positions:self.boxPositions
	                     sizes:self.boxSizes
	                    colors:self.boxColors
	                     count:self.boxCount];

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
		float blurRadii[] = {self.blurRadius, self.blurRadius, self.blurRadius};

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
		        self.blurRadius,
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
	simd_float2 resolution = self.size * self.scaleFactor;

	[encoder setRenderPipelineState:self.pipelineState];

	[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:0];
	[encoder setVertexBytes:&_scaleFactor length:sizeof(_scaleFactor) atIndex:1];
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
		[encoder copyFromTexture:target toTexture:self.offscreenTexture];
		[encoder endEncoding];
	}

	simd_float2 resolution = self.size * self.scaleFactor;

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
			descriptor.colorAttachments[0].texture = self.offscreenTexture;
		}

		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;

		encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

		switch (self.blurImplementation)
		{
			case BlurImplementation_SampleEveryPixel:
				[encoder setRenderPipelineState:
				                 self.pipelineStateBlurSampleEveryPixel];
				break;

			case BlurImplementation_SamplePixelQuads:
				[encoder setRenderPipelineState:
				                 self.pipelineStateBlurSamplePixelQuads];
				break;

			case BlurImplementation__Count: break;
		}

		[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:0];
		[encoder setVertexBytes:&_scaleFactor length:sizeof(_scaleFactor) atIndex:1];
		[encoder setVertexBytes:positions length:sizeof(simd_float2) * count atIndex:2];
		[encoder setVertexBytes:sizes length:sizeof(simd_float2) * count atIndex:3];
		[encoder setFragmentBytes:&resolution length:sizeof(resolution) atIndex:0];
		[encoder setFragmentBytes:&_scaleFactor length:sizeof(_scaleFactor) atIndex:1];
		[encoder setFragmentBytes:&horizontal length:sizeof(horizontal) atIndex:2];
		[encoder setFragmentBytes:blurRadii length:sizeof(float) * count atIndex:3];

		if (horizontal)
		{
			[encoder setFragmentTexture:self.offscreenTexture atIndex:0];
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

- (void)setSize:(simd_float2)size scaleFactor:(float)scaleFactor
{
	self.size = size;
	self.scaleFactor = scaleFactor;

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = (NSUInteger)(self.size.x * self.scaleFactor);
	descriptor.height = (NSUInteger)(self.size.y * self.scaleFactor);
	descriptor.self.pixelFormat = self.pixelFormat;
	descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
	descriptor.storageMode = MTLStorageModePrivate;

	self.offscreenTexture = [self.device newTextureWithDescriptor:descriptor];
	self.offscreenTexture.label = @"Offscreen Texture";
}

@end
