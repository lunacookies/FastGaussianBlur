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
VertexFunction(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 &resolution, constant float &scale_factor, const device float2 *positions,
        const device float2 *sizes, const device float4 *colors)
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
FragmentFunction(RasterizerData input [[stage_in]], metal::texture2d<float> blur_texture)
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
BlurVertexFunction(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 &resolution, constant float &scale_factor,
        constant float &output_scale_factor, const device float2 *positions,
        const device float2 *sizes)
{
	float2 position = positions[instance_id] * scale_factor;
	float2 size = sizes[instance_id] * scale_factor;

	BlurRasterizerData output = {0};
	float2 uv = UVFromScreenSpace(vertex_id, position, size, resolution);
	output.position = NDCFromUV(uv);
	output.p0 = position * output_scale_factor;
	output.p1 = (position + size) * output_scale_factor;
	output.instance_id = instance_id;
	return output;
}

float4
Blur(BlurRasterizerData input, float2 resolution, float blur_radius, uint horizontal,
        metal::texture2d<float> behind, float sample_offset_step, float sample_offset_nudge)
{
	metal::sampler sampler(metal::filter::linear, metal::address::mirrored_repeat);

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
		float weight =
		        metal::exp(-(float)(sample_offset * sample_offset) / (2 * sigma * sigma));

		result += sample * weight;
		total_weight += weight;
	}

	result /= total_weight;

	return result;
}

fragment float4
BlurFragmentFunctionSampleEveryPixel(BlurRasterizerData input [[stage_in]],
        constant float2 &resolution, constant float &scale_factor, constant uint &horizontal,
        const device float *blur_radii, metal::texture2d<float> behind)
{
	float blur_radius = blur_radii[input.instance_id] * scale_factor;
	return Blur(input, resolution, blur_radius, horizontal, behind, 1, 0);
}

fragment float4
BlurFragmentFunctionSamplePixelQuads(BlurRasterizerData input [[stage_in]],
        constant float2 &resolution, constant float &scale_factor, constant uint &horizontal,
        const device float *blur_radii, metal::texture2d<float> behind)
{
	float blur_radius = blur_radii[input.instance_id] * scale_factor;
	return Blur(input, resolution, blur_radius, horizontal, behind, 2, 0.5);
}

kernel void
SampleEveryPixel(uint2 thread_position_int [[thread_position_in_grid]], constant uint &horizontal,
        constant float2 &resolution, constant float2 &position, constant float2 &size,
        constant float &blur_radius, metal::texture2d<float, metal::access::write> destination,
        metal::texture2d<float> source)
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
