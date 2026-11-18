shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Clear shallow creek: a transparent ribbon whose UV.x runs across the stream.
// The edges fade out, and two travelling ripple bands break up the surface.
uniform vec4 shallow_color : source_color = vec4(0.36, 0.70, 0.68, 0.38);
uniform vec4 deep_color : source_color = vec4(0.08, 0.30, 0.32, 0.68);
uniform float flow_speed : hint_range(0.0, 3.0) = 0.45;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.45;

varying vec2 creek_uv;

void vertex() {
	creek_uv = UV;
}

void fragment() {
	float edge = smoothstep(0.0, 0.10, creek_uv.x) * smoothstep(1.0, 0.90, creek_uv.x);
	float along = creek_uv.y * 3.0;
	float bend = sin(along * 2.0 + TIME * flow_speed * 2.0) * 0.5 + 0.5;
	float fine = sin(along * 7.0 - TIME * flow_speed * 4.0 + creek_uv.x * 8.0) * 0.5 + 0.5;
	float depth = smoothstep(0.0, 0.45, abs(creek_uv.x - 0.5));
	vec3 colour = mix(shallow_color.rgb, deep_color.rgb, depth * 0.75);
	colour *= mix(0.94, 1.06, bend * 0.5 + fine * 0.5);
	float alpha = mix(shallow_color.a, deep_color.a, depth) * edge;
	ALBEDO = colour;
	ALPHA = alpha;
	ROUGHNESS = 0.06;
	METALLIC = 0.05;
	SPECULAR = 0.8;
	NORMAL = normalize(vec3(
		(fine - 0.5) * 0.06 * ripple_strength,
		1.0,
		(bend - 0.5) * 0.05 * ripple_strength));
}
