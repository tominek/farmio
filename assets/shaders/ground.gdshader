shader_type spatial;
render_mode cull_back;

// Grass ground without extra geometry: soft patches of different greens from world-space
// noise, darker forest floor under trees (forest_map), optional grid overlay for placement.

uniform vec3 grass_a : source_color = vec3(0.525, 0.722, 0.353);
uniform vec3 grass_b : source_color = vec3(0.455, 0.663, 0.31);
uniform vec3 grass_dry : source_color = vec3(0.62, 0.71, 0.36);
uniform vec3 forest_floor : source_color = vec3(0.33, 0.47, 0.23);
uniform sampler2D forest_map : filter_linear, repeat_disable;  // r = tree presence per tile
uniform float map_size = 256.0;
uniform float tile = 3.0;
uniform float grid_strength = 0.0;
uniform vec4 highlight_rect = vec4(0.0);   // tiles: x, y, w, h
uniform vec3 highlight_color : source_color = vec3(0.4, 0.9, 0.4);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = vnoise(p * 0.035) * 0.6 + vnoise(p * 0.11) * 0.3 + vnoise(p * 0.5) * 0.1;
	vec3 col = mix(grass_b, grass_a, smoothstep(0.35, 0.65, n));
	col = mix(col, grass_dry, smoothstep(0.62, 0.8, vnoise(p * 0.02 + 13.0)) * 0.6);
	// small facet-like speckles
	col *= 0.96 + 0.08 * hash(floor(p * 1.3));
	vec2 tile_uv = p / tile;
	float forest = texture(forest_map, tile_uv / map_size).r;
	col = mix(col, forest_floor, smoothstep(0.2, 0.75, forest));
	if (grid_strength > 0.0) {
		vec2 g = abs(fract(tile_uv) - 0.5);
		float line = smoothstep(0.47, 0.49, max(g.x, g.y));
		col = mix(col, vec3(1.0), line * grid_strength);
	}
	if (highlight_rect.z > 0.0 && tile_uv.x >= highlight_rect.x && tile_uv.y >= highlight_rect.y
			&& tile_uv.x < highlight_rect.x + highlight_rect.z && tile_uv.y < highlight_rect.y + highlight_rect.w) {
		col = mix(col, highlight_color, 0.45);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
