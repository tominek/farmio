shader_type spatial;

// Field soil without geometry: per-tile state from a data texture
// (r = state: 0 bare, 1/3 cultivated, 2/3 planted, 1 stubble; g = growth).
// Furrows run along x (5 per tile, matching the crop rows). Under a growing crop the soil
// is tinted green → ripe colour so a field reads dense from far away.

uniform sampler2D tiles : filter_nearest;
uniform vec2 field_origin;     // anchor in tiles
uniform vec2 field_size;       // tiles
uniform float tile = 3.0;
uniform vec3 bare : source_color = vec3(0.56, 0.43, 0.30);
uniform vec3 tilled : source_color = vec3(0.43, 0.30, 0.20);
uniform vec3 furrow : source_color = vec3(0.34, 0.23, 0.15);
uniform vec3 crop_green : source_color = vec3(0.40, 0.58, 0.24);
uniform vec3 crop_ripe : source_color = vec3(0.78, 0.66, 0.33);
uniform vec2 ripe_range = vec2(0.7, 1.0);
uniform vec3 stubble : source_color = vec3(0.66, 0.55, 0.36);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 t = world_pos.xz / tile - field_origin;
	vec4 d = texture(tiles, (floor(t) + 0.5) / field_size);
	float state = d.r * 3.0;
	float g = d.g;
	float row = fract(t.y * 5.0);
	float ridge = smoothstep(0.15, 0.35, row) * (1.0 - smoothstep(0.65, 0.85, row));
	vec3 col = bare;
	if (state > 0.5) {
		col = mix(furrow, tilled, ridge);
	}
	if (state > 1.5 && state < 2.5) {
		vec3 tint = mix(crop_green, crop_ripe, smoothstep(ripe_range.x, ripe_range.y, g));
		col = mix(col, tint, smoothstep(0.1, 0.55, g) * 0.75 * (0.6 + 0.4 * ridge));
	}
	if (state > 2.5) {
		col = mix(mix(furrow, tilled, ridge), stubble, 0.55);
	}
	col *= 0.95 + 0.1 * hash(floor(world_pos.xz * 2.0));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
