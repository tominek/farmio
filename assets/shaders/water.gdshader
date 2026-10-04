shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Water surface: a few slow swells move the surface up and down by a few centimetres, finer
// ripples only bend the normal. Colour by how deep the bed lies below (depth texture), lighter
// crests, a light rim where the water meets the bank (it laps with the swell), soft glints.

uniform vec3 shallow : source_color = vec3(0.36, 0.62, 0.7);
uniform vec3 deep : source_color = vec3(0.17, 0.39, 0.5);
uniform vec3 rim : source_color = vec3(0.86, 0.93, 0.93);
uniform vec3 glint : source_color = vec3(0.78, 0.9, 0.94);
uniform float swell_height = 0.05;       // metres
uniform float ripple_strength = 0.7;
uniform float glint_amount = 0.32;      // light ripple streaks drifting over the surface
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

// swells: direction, wavelength (m), speed (m/s), relative height
const vec4 WAVES[3] = vec4[](
	vec4(0.8, 0.6, 9.0, 0.6),
	vec4(-0.4, 0.9, 5.5, 0.45),
	vec4(0.3, -0.95, 4.5, 0.35)
);
const float WAVE_H[3] = float[](1.0, 0.6, 0.35);

// height of the swells and its slope (d/dx, d/dz) at a point
vec3 swell(vec2 p, float t) {
	float h = 0.0;
	vec2 d = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 dir = normalize(WAVES[i].xy);
		float k = 6.2831 / WAVES[i].z;
		float ph = k * (dot(dir, p) - WAVES[i].w * t);
		h += WAVE_H[i] * sin(ph);
		d += WAVE_H[i] * k * cos(ph) * dir;
	}
	return vec3(h, d) * swell_height;
}

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
	VERTEX.y += swell(world_pos.xz, TIME).x;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 s = swell(p, TIME);

	// fine ripples: slope of two drifting noise layers (finite differences)
	vec2 q1 = p * 1.3 + TIME * vec2(0.35, 0.2);
	vec2 q2 = p * 2.1 - TIME * vec2(0.15, 0.4);
	float e = 0.15;
	float n0 = vnoise(q1) + 0.6 * vnoise(q2);
	float nx = vnoise(q1 + vec2(e, 0.0)) + 0.6 * vnoise(q2 + vec2(e, 0.0));
	float nz = vnoise(q1 + vec2(0.0, e)) + 0.6 * vnoise(q2 + vec2(0.0, e));
	vec2 slope = s.yz + vec2(nx - n0, nz - n0) / e * ripple_strength * 0.1;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// thickness of the water along the view ray: scene depth behind minus the surface
	float d = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	behind.xyz /= behind.w;
	float thick = max(VERTEX.z - behind.z, 0.0);

	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.2, thick));
	col += s.x / swell_height * 0.045;                     // lighter crests, darker troughs
	col += (n0 - 0.8) * 0.07;
	// glints: thin bright streaks where two drifting ripple layers peak together
	float g = vnoise(p * 0.9 + TIME * vec2(0.45, 0.25)) * vnoise(p * 1.7 - TIME * vec2(0.2, 0.5));
	col = mix(col, glint, smoothstep(0.42, 0.62, g) * glint_amount);
	float edge = 1.0 - smoothstep(0.0, 0.1 + n0 * 0.06, thick);
	col = mix(col, rim, edge * 0.7);
	ALBEDO = col;
	ALPHA = clamp(mix(0.55, 0.92, smoothstep(0.0, 0.7, thick)) + edge * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.22;
	SPECULAR = 0.4;
}
