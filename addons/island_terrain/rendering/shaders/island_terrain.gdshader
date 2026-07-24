shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_texture : filter_linear_mipmap, repeat_disable;
uniform float world_size_m = 4096.0;
uniform float max_height_m = 512.0;
uniform float sea_level_m = 0.0;
uniform float outside_depth_m = 32.0;
uniform vec2 terrain_origin_world_xz = vec2(0.0);
instance uniform float lod_level = 0.0;
instance uniform float skirt_depth_m = 8.0;
uniform vec3 low_color : source_color = vec3(0.20, 0.31, 0.12);
uniform vec3 high_color : source_color = vec3(0.28, 0.25, 0.20);
uniform vec3 rock_color : source_color = vec3(0.32, 0.31, 0.29);
uniform float roughness_value = 0.92;

varying float terrain_height_m;
varying float terrain_slope;

float terrain_inside(vec2 terrain_uv) {
	return step(0.0, terrain_uv.x) * step(terrain_uv.x, 1.0)
		* step(0.0, terrain_uv.y) * step(terrain_uv.y, 1.0);
}

float sample_height(vec2 terrain_uv, float mip_level) {
	vec2 safe_uv = clamp(terrain_uv, vec2(0.0), vec2(1.0));
	return textureLod(height_texture, safe_uv, mip_level).r * terrain_inside(terrain_uv);
}

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 terrain_uv = (world_vertex.xz - terrain_origin_world_xz) / max(world_size_m, 1.0) + vec2(0.5);
	float mip_level = clamp(lod_level, 0.0, 6.0);
	float height_normalized = sample_height(terrain_uv, mip_level);
	float sampled_height_m = sea_level_m + height_normalized * max_height_m;
	float inside = terrain_inside(terrain_uv);
	terrain_height_m = mix(sea_level_m - outside_depth_m, sampled_height_m, inside);

	ivec2 image_size = textureSize(height_texture, 0);
	float mip_scale = exp2(mip_level);
	vec2 texel = vec2(mip_scale) / vec2(max(image_size, ivec2(1)));
	float h_l = sample_height(terrain_uv - vec2(texel.x, 0.0), mip_level) * max_height_m;
	float h_r = sample_height(terrain_uv + vec2(texel.x, 0.0), mip_level) * max_height_m;
	float h_d = sample_height(terrain_uv - vec2(0.0, texel.y), mip_level) * max_height_m;
	float h_u = sample_height(terrain_uv + vec2(0.0, texel.y), mip_level) * max_height_m;
	float meters_per_texel = world_size_m / float(max(image_size.x - 1, 1)) * mip_scale;
	vec3 terrain_normal = normalize(vec3(h_l - h_r, meters_per_texel * 2.0, h_d - h_u));
	NORMAL = terrain_normal;
	terrain_slope = 1.0 - clamp(terrain_normal.y, 0.0, 1.0);

	VERTEX.y = terrain_height_m - skirt_depth_m * COLOR.r;
}

void fragment() {
	float elevation_mix = smoothstep(sea_level_m + max_height_m * 0.10, sea_level_m + max_height_m * 0.72, terrain_height_m);
	vec3 ground = mix(low_color, high_color, elevation_mix);
	float rock_mix = smoothstep(0.28, 0.72, terrain_slope);
	ALBEDO = mix(ground, rock_color, rock_mix);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.18;
}
