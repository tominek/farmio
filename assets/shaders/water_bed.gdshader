shader_type spatial;
render_mode cull_disabled;

// River / pond bed: grassy top of the bank, bare earth on the slope, mud and sand under water.

uniform vec3 bank_grass : source_color = vec3(0.455, 0.6, 0.29);
uniform vec3 bank_soil : source_color = vec3(0.55, 0.42, 0.29);
uniform vec3 mud : source_color = vec3(0.36, 0.29, 0.21);
uniform vec3 sand : source_color = vec3(0.6, 0.53, 0.38);

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
	float y = world_pos.y;
	float n = vnoise(world_pos.xz * 0.6);
	vec3 col = mix(bank_soil, bank_grass, smoothstep(-0.2, -0.05, y + (n - 0.5) * 0.1));
	col = mix(mix(mud, sand, smoothstep(0.55, 0.75, vnoise(world_pos.xz * 0.15))), col, smoothstep(-0.55, -0.3, y));
	col *= 0.94 + 0.12 * hash(floor(world_pos.xz * 2.0));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
