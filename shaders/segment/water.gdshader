shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Quiet pond water. The mesh is a square plane; the fragment shader fades it
// out radially so the pond reads as a soft-edged disc, and drifts two sine
// waves through the albedo/normal for a gentle ripple.

uniform vec4 tint : source_color = vec4(0.16, 0.31, 0.33, 0.70);
uniform float edge_softness : hint_range(0.01, 0.4) = 0.12;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.55;
uniform float ripple_speed : hint_range(0.0, 3.0) = 1.0;

varying vec2 pond_uv;

void vertex() {
	pond_uv = UV * 2.0 - 1.0;
}

void fragment() {
	float distance_from_center = length(pond_uv);
	float alpha = smoothstep(1.0, 1.0 - edge_softness, distance_from_center);

	float wave_a = sin(pond_uv.x * 11.0 + TIME * 1.15 * ripple_speed) * 0.5 + 0.5;
	float wave_b = cos(pond_uv.y * 8.0 - TIME * 0.85 * ripple_speed) * 0.5 + 0.5;
	float shimmer = mix(0.86, 1.0, wave_a * 0.6 + wave_b * 0.4);

	vec3 normal = normalize(vec3(
		(wave_a - 0.5) * 0.20 * ripple_strength,
		1.0,
		(wave_b - 0.5) * 0.16 * ripple_strength));
	float fresnel = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = tint.rgb * shimmer * mix(0.92, 1.22, fresnel);
	ALPHA = tint.a * alpha * (0.94 + 0.06 * fresnel);
	ROUGHNESS = mix(0.16, 0.05, fresnel);
	METALLIC = 0.05;
	SPECULAR = 0.7;
	NORMAL = normal;
}
