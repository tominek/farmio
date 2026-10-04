shader_type spatial;
render_mode cull_back;

// Grass ground without extra geometry: soft patches of different greens from world-space
// noise, darker forest floor under trees (forest_map), optional grid overlay for placement.

uniform vec3 grass_a : source_color = vec3(0.525, 0.722, 0.353);
uniform vec3 grass_b : source_color = vec3(0.455, 0.663, 0.31);
uniform vec3 grass_dry : source_color = vec3(0.62, 0.71, 0.36);
uniform vec3 forest_floor : source_color = vec3(0.33, 0.47, 0.23);
uniform sampler2D forest_map : filter_linear, repeat_disable;  // r = tree presence per tile
// r = 1 on water tiles; the grass is cut away where the smoothed mask passes WATER_CUT and the
// river bed mesh (WaterView, same smoothing) shows through
uniform sampler2D water_map : filter_linear, repeat_disable;
const float WATER_CUT = 0.42;
uniform float map_size = 256.0;
uniform float tile = 3.0;
uniform float grid_strength = 0.0;
uniform vec4 highlight_rect = vec4(0.0);   // tiles: x, y, w, h
uniform vec3 highlight_color : source_color = vec3(0.4, 0.9, 0.4);
// Tool marks (GroundView.mark): rounded rectangles in tiles with a fill (alpha = strength), an inner
// edge line and an outer ring (alpha 0 = none), sizes in screen pixels at 1080p; dash > 0 dashes the edge.
uniform vec4 mark_rect[6];
uniform vec4 mark_fill[6] : source_color;
uniform vec4 mark_edge[6] : source_color;
uniform vec4 mark_ring[6] : source_color;
uniform float mark_dash[6];

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
	if (texture(water_map, p / tile / map_size).r > WATER_CUT) {
		discard;
	}
	float n =vnoise(p * 0.035) * 0.6 + vnoise(p * 0.11) * 0.3 + vnoise(p * 0.5) * 0.1;
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
	// metres per screen pixel, scaled so the sizes match the 1080p UI
	float px = length(fwidth(p)) * 0.7071 * VIEWPORT_SIZE.y / 1080.0;
	for (int i = 0; i < 6; i++) {
		vec4 r = mark_rect[i];
		if (r.z <= 0.0) {
			continue;
		}
		vec2 half_size = r.zw * tile * 0.5;
		vec2 q = p - (r.xy * tile + half_size);
		float rad = min(8.0 * px, min(half_size.x, half_size.y));
		vec2 e = abs(q) - half_size + rad;
		float d = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0) - rad;   // < 0 inside
		float aa = px;
		float inside = 1.0 - smoothstep(-aa, 0.0, d);
		col = mix(col, mark_fill[i].rgb, mark_fill[i].a * inside);
		float edge = smoothstep(-3.0 * px - aa, -3.0 * px, d) * inside;
		if (mark_dash[i] > 0.0) {
			// along the nearer side: x on the top and bottom, y on the left and right
			float along = (half_size.x - abs(q.x) < half_size.y - abs(q.y)) ? q.y : q.x;
			edge *= step(fract(along / (mark_dash[i] * px)), 0.6);
		}
		col = mix(col, mark_edge[i].rgb, mark_edge[i].a * edge);
		float ring = smoothstep(0.0, aa, d) * (1.0 - smoothstep(3.0 * px, 3.0 * px + aa, d));
		col = mix(col, mark_ring[i].rgb, mark_ring[i].a * ring);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
