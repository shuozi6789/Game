shader_type canvas_item;
// Cheap full-screen vignette for the HD2D cinematic framing.
// Drawn as a full-rect ColorRect in a CanvasLayer above the 3D viewport.

uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float inner : hint_range(0.0, 1.5) = 0.55;
uniform float outer : hint_range(0.0, 2.0) = 1.05;
uniform vec3 tint : source_color = vec3(0.03, 0.06, 0.03);

void fragment() {
	vec2 centered = UV - 0.5;
	// Slight horizontal stretch keeps the oval in step with the 16:9 frame.
	float d = length(centered * vec2(1.55, 1.0)) * 1.35;
	float v = smoothstep(inner, outer, d);
	COLOR = vec4(tint, v * strength);
}
