typedef uint32_t BlurImplementation;

typedef enum : BlurImplementation
{
	BlurImplementationAlgo_Fragment = 0b00 << 2,
	BlurImplementationAlgo_Compute = 0b01 << 2,
	BlurImplementationAlgo_LineCache = 0b10 << 2,
} BlurImplementationAlgo;

enum : BlurImplementation
{
	BlurImplementationFlag_TextureFiltering = 1 << 0,
	BlurImplementationFlag_QuarterRes = 1 << 1,
	BlurImplementation_AlgoMask = 0b11 << 2,
	BlurImplementation__Count = 0b1011 + 1,
};

static NSString *
StringFromBlurImplementation(BlurImplementation implementation)
{
	NSMutableString *result = [[NSMutableString alloc] init];

	BlurImplementationAlgo algo = implementation & BlurImplementation_AlgoMask;
	switch (algo)
	{
		case BlurImplementationAlgo_Fragment: [result appendString:@"Fragment"]; break;
		case BlurImplementationAlgo_Compute: [result appendString:@"Compute"]; break;
		case BlurImplementationAlgo_LineCache: [result appendString:@"Line Cache"]; break;
	}

	if (implementation & BlurImplementationFlag_TextureFiltering)
	{
		[result appendString:@" · Texture Filtering"];
	}

	if (implementation & BlurImplementationFlag_QuarterRes)
	{
		[result appendString:@" · ¼ Res"];
	}

	return result;
}

@interface Renderer : NSObject

@property id<MTLDevice> device;
@property id<MTLCommandQueue> commandQueue;

@property simd_float2 size;
@property float scaleFactor;
@property MTLPixelFormat pixelFormat;
@property id<MTLTexture> offscreenTexture1;
@property id<MTLTexture> offscreenTexture2;
@property id<MTLTexture> offscreenTextureQuarterRes1;
@property id<MTLTexture> offscreenTextureQuarterRes2;

@property id<MTLRenderPipelineState> pipelineState;
@property id<MTLRenderPipelineState> pipelineStateFragmentNoTextureFiltering;
@property id<MTLRenderPipelineState> pipelineStateFragmentTextureFiltering;
@property id<MTLComputePipelineState> pipelineStateComputeNoTextureFiltering;
@property id<MTLComputePipelineState> pipelineStateComputeTextureFiltering;
@property id<MTLComputePipelineState> pipelineStateLineCache;

@property MPSImageBilinearScale *downscaleKernel;

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
		descriptor.vertexFunction = [library newFunctionWithName:@"Vertex"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"Fragment"];
		self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor
		                                                                 error:nil];
	}

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertex"];
		descriptor.fragmentFunction =
		        [library newFunctionWithName:@"BlurFragmentNoTextureFiltering"];
		self.pipelineStateFragmentNoTextureFiltering =
		        [self.device newRenderPipelineStateWithDescriptor:descriptor error:nil];
	}

	{
		MTLRenderPipelineDescriptor *descriptor =
		        [[MTLRenderPipelineDescriptor alloc] init];
		descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
		descriptor.vertexFunction = [library newFunctionWithName:@"BlurVertex"];
		descriptor.fragmentFunction =
		        [library newFunctionWithName:@"BlurFragmentTextureFiltering"];
		self.pipelineStateFragmentTextureFiltering =
		        [self.device newRenderPipelineStateWithDescriptor:descriptor error:nil];
	}

	{
		self.pipelineStateComputeNoTextureFiltering = [self.device
		        newComputePipelineStateWithFunction:
		                [library newFunctionWithName:@"BlurComputeNoTextureFiltering"]
		                                      error:nil];
	}

	{
		self.pipelineStateComputeTextureFiltering = [self.device
		        newComputePipelineStateWithFunction:
		                [library newFunctionWithName:@"BlurComputeTextureFiltering"]
		                                      error:nil];
	}

	{
		self.pipelineStateLineCache =
		        [self.device newComputePipelineStateWithFunction:
		                             [library newFunctionWithName:@"BlurLineCache"]
		                                                   error:nil];
	}

	self.downscaleKernel = [[MPSImageBilinearScale alloc] initWithDevice:self.device];

	MPSScaleTransform downscaleTransform = {0};
	downscaleTransform.scaleX = 0.5;
	downscaleTransform.scaleY = 0.5;
	self.downscaleKernel.scaleTransform = &downscaleTransform;

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

	{
		MTLRenderPassDescriptor *descriptor =
		        [MTLRenderPassDescriptor renderPassDescriptor];
		descriptor.colorAttachments[0].texture = target;
		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
		descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1);

		id<MTLRenderCommandEncoder> encoder =
		        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

		[self drawBoxesWithEncoder:encoder
		               blurTexture:self.offscreenTexture1
		                 positions:self.boxPositions
		                     sizes:self.boxSizes
		                    colors:self.boxColors
		                     count:self.boxCount];

		[encoder endEncoding];
	}

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

		id<MTLTexture> blurTexture = [self blurWithCommandBuffer:commandBuffer
		                                                  target:target
		                                               positions:positions
		                                                   sizes:sizes
		                                               blurRadii:blurRadii
		                                                   count:3];

		MTLRenderPassDescriptor *descriptor =
		        [MTLRenderPassDescriptor renderPassDescriptor];
		descriptor.colorAttachments[0].texture = target;
		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;

		id<MTLRenderCommandEncoder> encoder =
		        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

		[self drawBoxesWithEncoder:encoder
		               blurTexture:blurTexture
		                 positions:positions
		                     sizes:sizes
		                    colors:colors
		                     count:3];

		[encoder endEncoding];
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

		id<MTLTexture> blurTexture = [self blurWithCommandBuffer:commandBuffer
		                                                  target:target
		                                               positions:positions
		                                                   sizes:sizes
		                                               blurRadii:blurRadii
		                                                   count:1];

		MTLRenderPassDescriptor *descriptor =
		        [MTLRenderPassDescriptor renderPassDescriptor];
		descriptor.colorAttachments[0].texture = target;
		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;

		id<MTLRenderCommandEncoder> encoder =
		        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

		[self drawBoxesWithEncoder:encoder
		               blurTexture:blurTexture
		                 positions:positions
		                     sizes:sizes
		                    colors:colors
		                     count:1];

		[encoder endEncoding];
	}

	return commandBuffer;
}

- (void)drawBoxesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                 blurTexture:(id<MTLTexture>)blurTexture
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
	[encoder setFragmentTexture:blurTexture atIndex:0];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:count];
}

- (id<MTLTexture>)blurWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 target:(id<MTLTexture>)target
                              positions:(simd_float2 *)positions
                                  sizes:(simd_float2 *)sizes
                              blurRadii:(float *)blurRadii
                                  count:(uint64_t)count
{
	float outputScaleFactor = 0;

	if (self.blurImplementation & BlurImplementationFlag_QuarterRes)
	{
		outputScaleFactor = 0.5;
		[self.downscaleKernel encodeToCommandBuffer:commandBuffer
		                              sourceTexture:target
		                         destinationTexture:self.offscreenTextureQuarterRes1];
	}
	else
	{
		outputScaleFactor = 1;
	}

	simd_float2 resolution = self.size * self.scaleFactor;

	simd_float2 downscaledResolution = resolution * outputScaleFactor;
	float downscaledScaleFactor = self.scaleFactor * outputScaleFactor;

	id<MTLTexture> sourceTexture = nil;
	id<MTLTexture> destinationTexture = nil;

	for (uint32_t horizontal = 0; horizontal <= 1; horizontal++)
	{
		if (self.blurImplementation & BlurImplementationFlag_QuarterRes)
		{
			if (horizontal)
			{
				destinationTexture = self.offscreenTextureQuarterRes1;
				sourceTexture = self.offscreenTextureQuarterRes2;
			}
			else
			{
				destinationTexture = self.offscreenTextureQuarterRes2;
				sourceTexture = self.offscreenTextureQuarterRes1;
			}
		}
		else
		{
			if (horizontal)
			{
				destinationTexture = self.offscreenTexture1;
				sourceTexture = self.offscreenTexture2;
			}
			else
			{
				destinationTexture = self.offscreenTexture2;
				sourceTexture = target;
			}
		}

		BlurImplementationAlgo algo = self.blurImplementation & BlurImplementation_AlgoMask;

		switch (algo)
		{
			case BlurImplementationAlgo_Fragment:
			{
				MTLRenderPassDescriptor *descriptor =
				        [MTLRenderPassDescriptor renderPassDescriptor];
				descriptor.colorAttachments[0].texture = destinationTexture;
				descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
				descriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;

				id<MTLRenderCommandEncoder> encoder = [commandBuffer
				        renderCommandEncoderWithDescriptor:descriptor];

				if (self.blurImplementation &
				        BlurImplementationFlag_TextureFiltering)
				{
					[encoder
					        setRenderPipelineState:
					                self.pipelineStateFragmentTextureFiltering];
				}
				else
				{
					[encoder
					        setRenderPipelineState:
					                self.pipelineStateFragmentNoTextureFiltering];
				}

				[encoder setVertexBytes:&resolution
				                 length:sizeof(resolution)
				                atIndex:0];
				[encoder setVertexBytes:&_scaleFactor
				                 length:sizeof(_scaleFactor)
				                atIndex:1];
				[encoder setVertexBytes:&outputScaleFactor
				                 length:sizeof(outputScaleFactor)
				                atIndex:2];
				[encoder setVertexBytes:positions
				                 length:sizeof(simd_float2) * count
				                atIndex:3];
				[encoder setVertexBytes:sizes
				                 length:sizeof(simd_float2) * count
				                atIndex:4];

				[encoder setFragmentBytes:&downscaledResolution
				                   length:sizeof(downscaledResolution)
				                  atIndex:0];
				[encoder setFragmentBytes:&downscaledScaleFactor
				                   length:sizeof(downscaledScaleFactor)
				                  atIndex:1];
				[encoder setFragmentBytes:&horizontal
				                   length:sizeof(horizontal)
				                  atIndex:2];
				[encoder setFragmentBytes:blurRadii
				                   length:sizeof(float) * count
				                  atIndex:3];
				[encoder setFragmentTexture:sourceTexture atIndex:0];

				[encoder drawPrimitives:MTLPrimitiveTypeTriangle
				            vertexStart:0
				            vertexCount:6
				          instanceCount:count];

				[encoder endEncoding];
			}
			break;

			case BlurImplementationAlgo_Compute:
			{
				id<MTLComputeCommandEncoder> encoder =
				        [commandBuffer computeCommandEncoderWithDispatchType:
				                               MTLDispatchTypeConcurrent];

				if (self.blurImplementation &
				        BlurImplementationFlag_TextureFiltering)
				{
					[encoder setComputePipelineState:
					                 self.pipelineStateComputeTextureFiltering];
				}
				else
				{
					[encoder
					        setComputePipelineState:
					                self.pipelineStateComputeNoTextureFiltering];
				}

				[encoder setBytes:&horizontal length:sizeof(horizontal) atIndex:0];
				[encoder setBytes:&downscaledResolution
				           length:sizeof(downscaledResolution)
				          atIndex:1];

				[encoder setTexture:destinationTexture atIndex:0];
				[encoder setTexture:sourceTexture atIndex:1];

				for (uint64_t i = 0; i < count; i++)
				{
					simd_float2 position = positions[i] * downscaledScaleFactor;
					simd_float2 size = sizes[i] * downscaledScaleFactor;
					float blurRadius = blurRadii[i] * downscaledScaleFactor;

					[encoder setBytes:&position
					           length:sizeof(position)
					          atIndex:2];
					[encoder setBytes:&size length:sizeof(size) atIndex:3];
					[encoder setBytes:&blurRadius
					           length:sizeof(blurRadius)
					          atIndex:4];

					MTLSize gridSize = MTLSizeMake((NSUInteger)ceilf(size.x),
					        (NSUInteger)ceilf(size.y), 1);

					[encoder dispatchThreads:gridSize
					        threadsPerThreadgroup:MTLSizeMake(32, 32, 1)];
				}

				[encoder endEncoding];
			}
			break;

			case BlurImplementationAlgo_LineCache:
			{
				id<MTLComputeCommandEncoder> encoder =
				        [commandBuffer computeCommandEncoderWithDispatchType:
				                               MTLDispatchTypeConcurrent];

				uint16_t threadgroupLength = (uint16_t)self.pipelineStateLineCache
				                                     .maxTotalThreadsPerThreadgroup;
				MTLSize threadgroupSize = {0};

				[encoder setComputePipelineState:self.pipelineStateLineCache];

				[encoder setThreadgroupMemoryLength:sizeof(simd_float4) *
				                                    threadgroupLength
				                            atIndex:0];

				if (horizontal)
				{
					threadgroupSize = MTLSizeMake(threadgroupLength, 1, 1);
				}
				else
				{
					threadgroupSize = MTLSizeMake(1, threadgroupLength, 1);
				}

				[encoder setBytes:&horizontal length:sizeof(horizontal) atIndex:0];
				[encoder setBytes:&downscaledResolution
				           length:sizeof(downscaledResolution)
				          atIndex:1];

				[encoder setTexture:destinationTexture atIndex:0];
				[encoder setTexture:sourceTexture atIndex:1];

				for (uint64_t i = 0; i < count; i++)
				{
					simd_float2 positionUnrounded =
					        positions[i] * downscaledScaleFactor;
					simd_float2 sizeUnrounded =
					        sizes[i] * downscaledScaleFactor;

					simd_float2 p0Unrounded = positionUnrounded;
					simd_float2 p1Unrounded = positionUnrounded + sizeUnrounded;

					simd_ushort2 p0 = 0;
					p0.x = (uint16_t)floorf(p0Unrounded.x);
					p0.y = (uint16_t)floorf(p0Unrounded.y);

					simd_ushort2 p1 = 0;
					p1.x = (uint16_t)ceilf(p1Unrounded.x);
					p1.y = (uint16_t)ceilf(p1Unrounded.y);

					simd_ushort2 size = p1 - p0;

					float blurRadius = blurRadii[i] * downscaledScaleFactor;

					// To avoid a performance cliff at high blur radii, make
					// sure there’s at least eight output-generating threads in
					// each threadgroup. At sufficiently-large threadgroup sizes
					// this should never happen.
					blurRadius = fmin(
					        blurRadius, (float)threadgroupLength * 0.5f - 8);

					[encoder setBytes:&p0 length:sizeof(p0) atIndex:2];
					[encoder setBytes:&p1 length:sizeof(p1) atIndex:3];
					[encoder setBytes:&blurRadius
					           length:sizeof(blurRadius)
					          atIndex:4];

					uint16_t sizeAlongCurrentDimension = 0;
					if (horizontal)
					{
						sizeAlongCurrentDimension = size.x;
					}
					else
					{
						sizeAlongCurrentDimension = size.y;
					}

					uint16_t blurRadiusInt = (uint16_t)ceilf(blurRadius);

					uint16_t threadgroupOutputSize =
					        threadgroupLength - 2 * blurRadiusInt;

					uint16_t fullThreadgroupCount =
					        sizeAlongCurrentDimension / threadgroupOutputSize;
					uint16_t fullThreadgroupThreadCount =
					        fullThreadgroupCount * threadgroupLength;

					uint16_t partialThreadgroupOutputSize =
					        sizeAlongCurrentDimension % threadgroupOutputSize;

					uint16_t partialThreadgroupThreadCount =
					        partialThreadgroupOutputSize + 2 * blurRadiusInt;

					uint16_t threadCount = fullThreadgroupThreadCount +
					                       partialThreadgroupThreadCount;

					MTLSize gridSize = {0};
					gridSize.depth = 1;
					if (horizontal)
					{
						gridSize.width = threadCount;
						gridSize.height = size.y;
					}
					else
					{
						gridSize.width = size.x;
						gridSize.height = threadCount;
					}

					[encoder dispatchThreads:gridSize
					        threadsPerThreadgroup:threadgroupSize];
				}

				[encoder endEncoding];
			}
			break;
		}
	}

	return destinationTexture;
}

- (void)setSize:(simd_float2)size scaleFactor:(float)scaleFactor
{
	self.size = size;
	self.scaleFactor = scaleFactor;

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = (NSUInteger)(self.size.x * self.scaleFactor);
	descriptor.height = (NSUInteger)(self.size.y * self.scaleFactor);
	descriptor.self.pixelFormat = self.pixelFormat;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead |
	                   MTLTextureUsageShaderWrite;
	descriptor.storageMode = MTLStorageModePrivate;

	self.offscreenTexture1 = [self.device newTextureWithDescriptor:descriptor];
	self.offscreenTexture2 = [self.device newTextureWithDescriptor:descriptor];
	self.offscreenTexture1.label = @"Offscreen Texture 1";
	self.offscreenTexture2.label = @"Offscreen Texture 2";

	descriptor.width /= 2;
	descriptor.height /= 2;

	self.offscreenTextureQuarterRes1 = [self.device newTextureWithDescriptor:descriptor];
	self.offscreenTextureQuarterRes2 = [self.device newTextureWithDescriptor:descriptor];
	self.offscreenTextureQuarterRes1.label = @"¼ Res Offscreen Texture 1";
	self.offscreenTextureQuarterRes2.label = @"¼ Res Offscreen Texture 2";
}

@end
