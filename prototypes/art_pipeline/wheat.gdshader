shader_type spatial;
render_mode cull_disabled;

// Continuous crop growth driven by INSTANCE_CUSTOM.r (0..1).
// The mesh is authored at full growth. Per-vertex data baked in Blender:
//   COLOR.rgb = part mask (r = leaf, g = stalk, b = ear)
//   COLOR.a   = pivot height / 1.5
//   UV2       = pivot x/z (plant base for leaves and stalks, stalk top for ears)

uniform vec3 leaf_young : source_color = vec3(0.549, 0.757, 0.322);
uniform vec3 leaf_mid : source_color = vec3(0.435, 0.639, 0.267);
uniform vec3 turning : source_color = vec3(0.749, 0.761, 0.353);
uniform vec3 straw : source_color = vec3(0.867, 0.729, 0.369);
uniform vec3 ear_green : source_color = vec3(0.616, 0.733, 0.306);
uniform vec3 ear_ripe : source_color = vec3(0.788, 0.604, 0.243);
uniform float ground_y = 0.11;
uniform float sway_strength = 0.03;

varying vec3 v_color;

void vertex() {
	float g = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	vec3 pivot = vec3(UV2.x, COLOR.a * 1.5, UV2.y);
	vec3 p = VERTEX;

	float leaf_f = smoothstep(0.0, 0.5, g) * (1.0 - 0.55 * smoothstep(0.75, 1.0, g));
	float stalk_f = clamp((g - 0.3) / 0.7, 0.0, 1.0);
	float ear_f = smoothstep(0.55, 1.0, g);

	vec3 green = mix(leaf_young, leaf_mid, smoothstep(0.1, 0.45, g));
	vec3 plant = mix(mix(green, turning, smoothstep(0.65, 0.82, g)), straw, smoothstep(0.82, 0.97, g));

	if (COLOR.r > 0.5) {
		p = pivot + (p - pivot) * leaf_f;
		v_color = plant;
	} else if (COLOR.g > 0.5) {
		// stalks grow vertically only, so their tops stay where the ears are attached
		p.y = pivot.y + (p.y - pivot.y) * stalk_f;
		v_color = plant;
	} else {
		vec3 moved = vec3(pivot.x, ground_y + (pivot.y - ground_y) * stalk_f, pivot.z);
		p = moved + (p - pivot) * ear_f;
		v_color = mix(ear_green, ear_ripe, smoothstep(0.72, 0.95, g));
	}

	// gentle wind, stronger towards the tips
	vec3 world = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	float h = max(p.y - ground_y, 0.0);
	p.x += sin(TIME * 1.3 + world.x * 0.35 + world.z * 0.2) * sway_strength * h;
	p.z += cos(TIME * 1.1 + world.z * 0.3) * sway_strength * 0.5 * h;

	if (g < 0.02) {
		p = pivot;
	}
	VERTEX = p;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
