#include <metal_stdlib>

constant float2 corners[] = {
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 1},
        {1, 0},
        {0, 0},
};

float2
UVFromScreenSpace(uint vertex_id, float2 position, float2 size, float2 resolution)
{
	float2 corner = corners[vertex_id];
	return (position + corner * size) / resolution;
}

float4
NDCFromUV(float2 uv)
{
	float4 result = float4(0, 0, 0, 1);
	result.xy = uv * 2 - 1;
	result.y *= -1;
	return result;
}

struct RasterizerData
{
	float4 position [[position]];
	float2 position_uv;
	float4 color;
};

vertex RasterizerData
Vertex(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]], constant float2 &resolution,
        constant float &scale_factor, const device float2 *positions, const device float2 *sizes,
        const device float4 *colors)
{
	float2 position = positions[instance_id] * scale_factor;
	float2 size = sizes[instance_id] * scale_factor;
	float4 color = colors[instance_id];

	RasterizerData output = {0};
	output.position_uv = UVFromScreenSpace(vertex_id, position, size, resolution);
	output.position = NDCFromUV(output.position_uv);
	output.color = color;
	output.color.rgb *= color.a;
	return output;
}

fragment float4
Fragment(RasterizerData input [[stage_in]], metal::texture2d<float> blur_texture)
{
	metal::sampler sampler(metal::filter::linear);
	float4 blurred_color = blur_texture.sample(sampler, input.position_uv);

	// Alpha composite box color over blurred color.
	float4 result = 0;
	result.rgb = input.color.rgb + blurred_color.rgb * (1 - input.color.a);
	result.a = input.color.a + blurred_color.a * (1 - input.color.a);
	return result;
}

struct BlurRasterizerData
{
	float4 position [[position]];
	float2 p0 [[flat]];
	float2 p1 [[flat]];
	uint instance_id;
};

vertex BlurRasterizerData
BlurVertex(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 &resolution, constant float &scale_factor,
        constant float &output_scale_factor, const device float2 *positions,
        const device float2 *sizes)
{
	float2 position = positions[instance_id] * scale_factor;
	float2 size = sizes[instance_id] * scale_factor;

	BlurRasterizerData output = {0};
	float2 uv = UVFromScreenSpace(vertex_id, position, size, resolution);
	output.position = NDCFromUV(uv);
	output.p0 = metal::max(position, 0) * output_scale_factor;
	output.p1 = metal::min(position + size, resolution) * output_scale_factor;
	output.instance_id = instance_id;
	return output;
}

float
Gaussian(float sigma, float x)
{
	return metal::exp(-(x * x) / (2 * sigma * sigma));
}

float4
Blur(BlurRasterizerData input, float2 resolution, float blur_radius, uint horizontal,
        metal::texture2d<float> behind, float sample_offset_step, float sample_offset_nudge)
{
	metal::sampler sampler(metal::filter::linear);

	float sigma = blur_radius * 0.2;
	short kernel_radius = (short)blur_radius;

	float4 result = 0;
	float total_weight = 0;

	float sample_offset_start = -kernel_radius;
	float sample_offset_end = kernel_radius + 1;

	if (horizontal)
	{
		sample_offset_start =
		        metal::max(sample_offset_start, input.p0.x - input.position.x);
		sample_offset_end = metal::min(sample_offset_end, input.p1.x - input.position.x);
	}
	else
	{
		sample_offset_start =
		        metal::max(sample_offset_start, input.p0.y - input.position.y);
		sample_offset_end = metal::min(sample_offset_end, input.p1.y - input.position.y);
	}

	float2 axis = 0;
	if (horizontal)
	{
		axis = float2(1, 0);
	}
	else
	{
		axis = float2(0, 1);
	}

	for (float sample_offset = sample_offset_start; sample_offset < sample_offset_end;
	        sample_offset += sample_offset_step)
	{
		float2 sample_position =
		        input.position.xy + (sample_offset + sample_offset_nudge) * axis;
		float4 sample = behind.sample(sampler, sample_position / resolution);
		float weight = Gaussian(sigma, sample_offset);

		result += sample * weight;
		total_weight += weight;
	}

	result /= total_weight;

	return result;
}

fragment float4
BlurFragmentNoTextureFiltering(BlurRasterizerData input [[stage_in]], constant float2 &resolution,
        constant float &scale_factor, constant uint &horizontal, const device float *blur_radii,
        metal::texture2d<float> behind)
{
	float blur_radius = blur_radii[input.instance_id] * scale_factor;
	return Blur(input, resolution, blur_radius, horizontal, behind, 1, 0);
}

fragment float4
BlurFragmentTextureFiltering(BlurRasterizerData input [[stage_in]], constant float2 &resolution,
        constant float &scale_factor, constant uint &horizontal, const device float *blur_radii,
        metal::texture2d<float> behind)
{
	float blur_radius = blur_radii[input.instance_id] * scale_factor;
	return Blur(input, resolution, blur_radius, horizontal, behind, 2, 0.5);
}

kernel void
BlurComputeNoTextureFiltering(uint2 thread_position_int [[thread_position_in_grid]],
        constant uint &horizontal, constant float2 &resolution, constant float2 &position,
        constant float2 &size, constant float &blur_radius,
        metal::texture2d<float, metal::access::write> destination, metal::texture2d<float> source)
{
	float2 thread_position = position + (float2)thread_position_int + 0.5;
	thread_position_int += (uint2)position;

	BlurRasterizerData data = {0};
	data.position = float4(thread_position, 0, 1);
	data.p0 = position;
	data.p1 = position + size;

	float4 output = Blur(data, resolution, blur_radius, horizontal, source, 1, 0);
	destination.write(output, thread_position_int);
}

kernel void
BlurComputeTextureFiltering(uint2 thread_position_int [[thread_position_in_grid]],
        constant uint &horizontal, constant float2 &resolution, constant float2 &position,
        constant float2 &size, constant float &blur_radius,
        metal::texture2d<float, metal::access::write> destination, metal::texture2d<float> source)
{
	float2 thread_position = position + (float2)thread_position_int + 0.5;
	thread_position_int += (uint2)position;

	BlurRasterizerData data = {0};
	data.position = float4(thread_position, 0, 1);
	data.p0 = position;
	data.p1 = position + size;

	float4 output = Blur(data, resolution, blur_radius, horizontal, source, 2, 0.5);
	destination.write(output, thread_position_int);
}

void
PopulateLineCache(ushort thread_index_in_threadgroup, threadgroup float4 *line_cache,
        ushort2 position_in_image, float2 resolution, metal::texture2d<float> behind)
{
	metal::sampler sampler(metal::filter::linear, metal::address::mirrored_repeat);
	float2 sample_position = ((float2)position_in_image + 0.5) / resolution;
	float4 sample = behind.sample(sampler, sample_position);
	line_cache[thread_index_in_threadgroup] = sample;

	metal::threadgroup_barrier(metal::mem_flags::mem_threadgroup);
}

float4
BlurAtImagePositionLineCache(ushort thread_index_in_threadgroup, threadgroup float4 *line_cache,
        uint horizontal, ushort2 position_in_image, ushort2 p0, ushort2 p1, float blur_radius)
{
	float sigma = blur_radius * 0.2;
	short kernel_radius = (short)blur_radius;

	float4 result = 0;
	float total_weight = 0;

	short sample_offset_start = -kernel_radius;
	short sample_offset_end = kernel_radius;

	if (horizontal)
	{
		sample_offset_start =
		        metal::max(sample_offset_start, (short)(p0.x - position_in_image.x));
		sample_offset_end =
		        metal::min(sample_offset_end, (short)(p1.x - position_in_image.x));
	}
	else
	{
		sample_offset_start =
		        metal::max(sample_offset_start, (short)(p0.y - position_in_image.y));
		sample_offset_end =
		        metal::min(sample_offset_end, (short)(p1.y - position_in_image.y));
	}

	for (short sample_offset = sample_offset_start; sample_offset <= sample_offset_end;
	        sample_offset++)
	{
		float4 sample = line_cache[thread_index_in_threadgroup + sample_offset];
		float weight = Gaussian(sigma, sample_offset);

		result += sample * weight;
		total_weight += weight;
	}

	result /= total_weight;
	return result;
}

kernel void
BlurLineCache(ushort2 threadgroup_position_in_grid [[threadgroup_position_in_grid]],
        ushort thread_index_in_threadgroup [[thread_index_in_threadgroup]],
        ushort2 threads_per_threadgroup [[threads_per_threadgroup]],
        ushort2 dispatch_threads_per_threadgroup [[dispatch_threads_per_threadgroup]],
        constant uint &horizontal, constant float2 &resolution, constant ushort2 &p0,
        constant ushort2 &p1, constant float &blur_radius, threadgroup float4 *line_cache,
        metal::texture2d<float, metal::access::write> destination, metal::texture2d<float> source)
{
	ushort blur_radius_int = (ushort)metal::ceil(blur_radius);

	ushort2 axis = 0;
	ushort threadgroup_length = 0;
	ushort2 dispatch_threadgroup_output_size = dispatch_threads_per_threadgroup;
	if (horizontal)
	{
		axis = ushort2(1, 0);
		threadgroup_length = threads_per_threadgroup.x;
		dispatch_threadgroup_output_size.x -= 2 * blur_radius_int;
	}
	else
	{
		axis = ushort2(0, 1);
		threadgroup_length = threads_per_threadgroup.y;
		dispatch_threadgroup_output_size.y -= 2 * blur_radius_int;
	}

	ushort2 position_in_image =
	        p0 + threadgroup_position_in_grid * dispatch_threadgroup_output_size +
	        axis * thread_index_in_threadgroup - axis * blur_radius_int;

	PopulateLineCache(
	        thread_index_in_threadgroup, line_cache, position_in_image, resolution, source);

	if (thread_index_in_threadgroup < blur_radius_int ||
	        thread_index_in_threadgroup >= threadgroup_length - blur_radius_int)
	{
		return;
	}

	float4 result = BlurAtImagePositionLineCache(thread_index_in_threadgroup, line_cache,
	        horizontal, position_in_image, p0, p1, blur_radius);
	destination.write(result, position_in_image);
}
