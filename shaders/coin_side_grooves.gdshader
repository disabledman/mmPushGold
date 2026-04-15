shader_type spatial;
render_mode specular_schlick_ggx;

// Procedural vertical grooves around the coin side.
// Assumes the side mesh has cylindrical UVs where UV.x wraps around.

uniform float groove_count = 48.0;          // number of grooves around circumference
uniform float groove_sharpness = 6.0;       // higher = thinner grooves
uniform float groove_depth = 0.06;          // normal perturbation strength
uniform vec3 base_color : source_color = vec3(0.90, 0.75, 0.20);
uniform float metallic = 0.8;
uniform float roughness = 0.3;

float groove_height(vec2 uv) {
	// Use a cosine wave around circumference; remap to 0..1 and sharpen.
	float t = uv.x * TAU * groove_count;
	float wave = 0.5 + 0.5 * cos(t);
	return pow(wave, groove_sharpness);
}

void fragment() {
	float h = groove_height(UV);

	// Subtle color modulation so grooves read even in flat lighting.
	float shade = mix(0.96, 1.0, h);
	ALBEDO = base_color * shade;

	METALLIC = metallic;
	ROUGHNESS = roughness;

	// Build a tangent-space normal from the procedural height field.
	// Use a small UV-space epsilon so it's stable across resolutions.
	float eps = 0.0015;
	float hx = groove_height(UV + vec2(eps, 0.0));
	float hy = groove_height(UV + vec2(0.0, eps));
	vec2 grad = vec2((hx - h) / eps, (hy - h) / eps);

	vec3 n_tangent = normalize(vec3(-grad.x * groove_depth, -grad.y * groove_depth, 1.0));
	NORMAL_MAP = n_tangent;
	NORMAL_MAP_DEPTH = 1.0;
}
