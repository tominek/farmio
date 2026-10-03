shader_type spatial;
render_mode cull_disabled;

// Continuous crop growth driven by INSTANCE_CUSTOM.r (0..1); one mesh authored at full growth.
// Per-vertex data baked in Blender:
//   COLOR.rgb = part mask (r = leaf, g = stalk, b = fruit: ear / cob / flower / crown)
//   COLOR.a   = pivot height / 1.5
//   UV2       = pivot x/z (plant base for leaves and stalks, attachment point for fruit)
// Parts attached higher up a stalk (corn leaves, cobs, ears) ride up with the growing stalk.

uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 leaf_young : source_color = vec3(0.549, 0.757, 0.322);
uniform vec3 leaf_mid : source_color = vec3(0.435, 0.639, 0.267);
uniform float leaf_use_palette = 0.0;      // 1 = mature leaf colour comes from the palette
uniform vec3 turning : source_color = vec3(0.749, 0.761, 0.353);
uniform vec3 ripe_plant : source_color = vec3(0.867, 0.729, 0.369);
uniform vec2 ripe_range = vec2(0.65, 0.97);
uniform float ripe_amount = 1.0;
uniform vec3 fruit_young : source_color = vec3(0.616, 0.733, 0.306);
uniform vec3 fruit_ripe : source_color = vec3(0.788, 0.604, 0.243);
uniform float fruit_use_palette = 0.0;
uniform float leaf_full = 0.5;             // growth at which leaves reach full size
uniform float leaf_wither = 0.55;          // how much leaves shrink when ripe
uniform vec2 stalk_range = vec2(0.3, 1.0);
uniform vec2 fruit_range = vec2(0.55, 1.0);
uniform float fruit_fade = 2.0;            // fruit disappears after this growth (potato flowers)
uniform float ground_y = 0.11;
uniform float sway_strength = 0.03;

varying vec3 v_color;

void vertex() {
	float g = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	vec3 pivot = vec3(UV2.x, COLOR.a * 1.5, UV2.y);
	vec3 p = VERTEX;

	float leaf_f = smoothstep(0.0, leaf_full, g) * (1.0 - leaf_wither * smoothstep(0.75, 1.0, g));
	float stalk_f = clamp((g - stalk_range.x) / (stalk_range.y - stalk_range.x), 0.0, 1.0);
	float fruit_f = smoothstep(fruit_range.x, fruit_range.y, g) * (1.0 - smoothstep(fruit_fade, fruit_fade + 0.08, g));
	vec3 moved = vec3(pivot.x, ground_y + (pivot.y - ground_y) * stalk_f, pivot.z);

	vec3 pal = textureLod(palette, UV, 0.0).rgb;
	vec3 green = mix(leaf_young, mix(leaf_mid, pal, leaf_use_palette), smoothstep(0.1, 0.45, g));
	float ripe = smoothstep(ripe_range.x, ripe_range.y, g) * ripe_amount;
	vec3 plant = mix(mix(green, turning, smoothstep(0.0, 0.5, ripe) * step(0.001, ripe)), ripe_plant, smoothstep(0.5, 1.0, ripe));

	if (COLOR.r > 0.5) {
		p = moved + (p - pivot) * leaf_f;
		v_color = plant;
	} else if (COLOR.g > 0.5) {
		// stalks grow vertically only, so their tops stay where the ears are attached
		p.y = pivot.y + (p.y - pivot.y) * stalk_f;
		v_color = plant;
	} else {
		p = moved + (p - pivot) * fruit_f;
		v_color = fruit_use_palette > 0.5 ? pal : mix(fruit_young, fruit_ripe, smoothstep(0.72, 0.95, g));
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
