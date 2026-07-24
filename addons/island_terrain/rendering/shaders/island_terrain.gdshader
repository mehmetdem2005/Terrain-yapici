shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_metadata_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_override_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D albedo_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2DArray albedo_array : filter_linear_mipmap, repeat_enable;

uniform float world_size_m = 4096.0;
uniform float max_height_m = 512.0;
uniform float sea_level_m = 0.0;
uniform float outside_depth_m = 32.0;
uniform vec2 terrain_origin_world_xz = vec2(0.0);

instance uniform float lod_level = 0.0;
instance uniform float skirt_depth_m = 8.0;

uniform int material_backend = 0;
uniform bool has_metadata_texture = false;
uniform bool has_override_texture = false;
uniform bool has_albedo_atlas = false;
uniform bool has_albedo_array = false;
uniform vec2 atlas_grid = vec2(4.0, 2.0);
uniform float detail_lod_limit = 2.0;
uniform float metadata_blend_strength = 1.0;

uniform vec3 sand_tint : source_color = vec3(0.72, 0.62, 0.40);
uniform float sand_slot = 0.0;
uniform float sand_meters_per_tile = 3.0;
uniform float sand_roughness = 0.92;
uniform float sand_metallic = 0.0;

uniform vec3 grass_tint : source_color = vec3(0.25, 0.39, 0.14);
uniform float grass_slot = 1.0;
uniform float grass_meters_per_tile = 2.5;
uniform float grass_roughness = 0.94;
uniform float grass_metallic = 0.0;

uniform vec3 forest_tint : source_color = vec3(0.10, 0.24, 0.09);
uniform float forest_slot = 2.0;
uniform float forest_meters_per_tile = 3.5;
uniform float forest_roughness = 0.96;
uniform float forest_metallic = 0.0;

uniform vec3 wetland_tint : source_color = vec3(0.18, 0.24, 0.13);
uniform float wetland_slot = 3.0;
uniform float wetland_meters_per_tile = 2.0;
uniform float wetland_roughness = 0.86;
uniform float wetland_metallic = 0.0;

uniform vec3 rock_tint : source_color = vec3(0.36, 0.35, 0.33);
uniform float rock_slot = 4.0;
uniform float rock_meters_per_tile = 4.5;
uniform float rock_roughness = 0.82;
uniform float rock_metallic = 0.0;

uniform vec3 mountain_tint : source_color = vec3(0.58, 0.59, 0.57);
uniform float mountain_slot = 5.0;
uniform float mountain_meters_per_tile = 6.0;
uniform float mountain_roughness = 0.88;
uniform float mountain_metallic = 0.0;

varying float terrain_height_m;
varying float terrain_slope;
varying vec2 terrain_uv_data;
varying vec3 terrain_world_position;


float terrain_inside(vec2 terrain_uv) {
	return step(0.0, terrain_uv.x) * step(terrain_uv.x, 1.0)
		* step(0.0, terrain_uv.y) * step(terrain_uv.y, 1.0);
}


float sample_height(vec2 terrain_uv, float mip_level) {
	vec2 safe_uv = clamp(terrain_uv, vec2(0.0), vec2(1.0));
	return textureLod(height_texture, safe_uv, mip_level).r * terrain_inside(terrain_uv);
}


float channel_match(float value, float target) {
	return 1.0 - smoothstep(0.30, 0.72, abs(value - target));
}


vec3 sample_atlas_layer(float slot, float meters_per_tile) {
	vec2 safe_grid = max(atlas_grid, vec2(1.0));
	vec2 cell_size = vec2(1.0) / safe_grid;
	vec2 cell = vec2(mod(slot, safe_grid.x), floor(slot / safe_grid.x));
	vec2 local_uv = fract(terrain_world_position.xz / max(meters_per_tile, 0.25));
	ivec2 atlas_size_i = textureSize(albedo_atlas, 0);
	vec2 atlas_size = vec2(max(atlas_size_i, ivec2(1)));
	vec2 inset = vec2(1.5) / atlas_size;
	vec2 minimum_uv = cell * cell_size + inset;
	vec2 maximum_uv = (cell + vec2(1.0)) * cell_size - inset;
	return texture(albedo_atlas, mix(minimum_uv, maximum_uv, local_uv)).rgb;
}


vec3 sample_array_layer(float slot, float meters_per_tile) {
	vec2 layer_uv = terrain_world_position.xz / max(meters_per_tile, 0.25);
	return texture(albedo_array, vec3(layer_uv, slot)).rgb;
}


vec3 layer_color(vec3 tint, float slot, float meters_per_tile) {
	bool detail_enabled = lod_level <= detail_lod_limit;
	if (detail_enabled && material_backend == 1 && has_albedo_atlas) {
		return sample_atlas_layer(slot, meters_per_tile) * tint;
	}
	if (detail_enabled && material_backend == 2 && has_albedo_array) {
		return sample_array_layer(slot, meters_per_tile) * tint;
	}
	return tint;
}


void vertex() {
	vec3 source_world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 terrain_uv = (source_world_vertex.xz - terrain_origin_world_xz)
		/ max(world_size_m, 1.0) + vec2(0.5);
	float mip_level = clamp(lod_level, 0.0, 7.0);
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
	terrain_uv_data = clamp(terrain_uv, vec2(0.0), vec2(1.0));

	VERTEX.y = terrain_height_m - skirt_depth_m * COLOR.r;
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec4 metadata = vec4(0.0, 0.45, 0.0, 0.0);
	if (has_metadata_texture) {
		metadata = texture(terrain_metadata_texture, terrain_uv_data);
	}
	vec4 override_data = vec4(0.0);
	if (has_override_texture) {
		override_data = texture(terrain_override_texture, terrain_uv_data);
	}

	float biome = mix(metadata.r * 7.0, override_data.r * 7.0, override_data.g);
	float moisture = metadata.g;
	float river = metadata.b;
	float elevation_normalized = clamp(
		(terrain_height_m - sea_level_m) / max(max_height_m, 0.001),
		0.0,
		1.0
	);

	float beach_band = smoothstep(0.0, 0.035, elevation_normalized)
		* (1.0 - smoothstep(0.035, 0.075, elevation_normalized));
	float sand_weight = max(channel_match(biome, 1.0), beach_band);
	float grass_weight = max(channel_match(biome, 2.0), channel_match(biome, 5.0) * 0.45);
	float forest_weight = channel_match(biome, 3.0) * smoothstep(0.34, 0.62, moisture);
	float wetland_weight = max(channel_match(biome, 4.0), river * smoothstep(0.20, 0.70, moisture));
	float mountain_weight = max(channel_match(biome, 6.0), smoothstep(0.64, 0.88, elevation_normalized));
	float rock_weight = max(channel_match(biome, 7.0), smoothstep(0.22, 0.70, terrain_slope));

	float base_total = sand_weight + grass_weight + forest_weight
		+ wetland_weight + rock_weight + mountain_weight;
	if (base_total < 0.001) {
		grass_weight = 1.0;
		base_total = 1.0;
	}
	float inverse_base = 1.0 / base_total;
	sand_weight *= inverse_base;
	grass_weight *= inverse_base;
	forest_weight *= inverse_base;
	wetland_weight *= inverse_base;
	rock_weight *= inverse_base;
	mountain_weight *= inverse_base;

	float manual_material = override_data.b * 5.0;
	float manual_strength = override_data.a;
	sand_weight = mix(sand_weight, channel_match(manual_material, 0.0), manual_strength);
	grass_weight = mix(grass_weight, channel_match(manual_material, 1.0), manual_strength);
	forest_weight = mix(forest_weight, channel_match(manual_material, 2.0), manual_strength);
	wetland_weight = mix(wetland_weight, channel_match(manual_material, 3.0), manual_strength);
	rock_weight = mix(rock_weight, channel_match(manual_material, 4.0), manual_strength);
	mountain_weight = mix(mountain_weight, channel_match(manual_material, 5.0), manual_strength);

	float total_weight = sand_weight + grass_weight + forest_weight
		+ wetland_weight + rock_weight + mountain_weight;
	float inverse_weight = 1.0 / max(total_weight, 0.001);
	sand_weight *= inverse_weight;
	grass_weight *= inverse_weight;
	forest_weight *= inverse_weight;
	wetland_weight *= inverse_weight;
	rock_weight *= inverse_weight;
	mountain_weight *= inverse_weight;

	vec3 albedo = layer_color(sand_tint, sand_slot, sand_meters_per_tile) * sand_weight;
	albedo += layer_color(grass_tint, grass_slot, grass_meters_per_tile) * grass_weight;
	albedo += layer_color(forest_tint, forest_slot, forest_meters_per_tile) * forest_weight;
	albedo += layer_color(wetland_tint, wetland_slot, wetland_meters_per_tile) * wetland_weight;
	albedo += layer_color(rock_tint, rock_slot, rock_meters_per_tile) * rock_weight;
	albedo += layer_color(mountain_tint, mountain_slot, mountain_meters_per_tile) * mountain_weight;

	float fallback_elevation = smoothstep(0.10, 0.72, elevation_normalized);
	vec3 fallback_color = mix(grass_tint, mountain_tint, fallback_elevation);
	fallback_color = mix(fallback_color, rock_tint, smoothstep(0.28, 0.72, terrain_slope));
	float metadata_mix = has_metadata_texture ? metadata_blend_strength : 0.0;
	ALBEDO = mix(fallback_color, albedo, max(metadata_mix, manual_strength));

	ROUGHNESS = sand_roughness * sand_weight
		+ grass_roughness * grass_weight
		+ forest_roughness * forest_weight
		+ wetland_roughness * wetland_weight
		+ rock_roughness * rock_weight
		+ mountain_roughness * mountain_weight;
	METALLIC = sand_metallic * sand_weight
		+ grass_metallic * grass_weight
		+ forest_metallic * forest_weight
		+ wetland_metallic * wetland_weight
		+ rock_metallic * rock_weight
		+ mountain_metallic * mountain_weight;
	SPECULAR = 0.18;
}
