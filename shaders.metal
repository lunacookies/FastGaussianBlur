constant float2 corners[] = {
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 1},
        {1, 0},
        {0, 0},
};

float4
NDCFromScreenSpace(uint vertex_id, float2 position, float2 size, float2 resolution)
{
	float2 corner = corners[vertex_id];
	float4 result = float4(0, 0, 0, 1);
	result.xy = (position + corner * size) / resolution * 2 - 1;
	result.y *= -1;
	return result;
}

struct RasterizerData
{
	float4 position [[position]];
	float4 color;
};

vertex RasterizerData
VertexFunction(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 &resolution, const device float2 *positions, const device float3 *colors,
        constant float2 &size)
{
	float2 position = positions[instance_id];
	float3 color = colors[instance_id];

	RasterizerData output = {0};
	output.position = NDCFromScreenSpace(vertex_id, position, size, resolution);
	output.color = float4(color, 1);
	return output;
}

fragment float4
FragmentFunction(RasterizerData input [[stage_in]])
{
	return input.color;
}
