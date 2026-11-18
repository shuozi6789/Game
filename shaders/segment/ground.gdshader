shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// Ground material with the trail baked in: the grass texture is blended with
// the dirt texture through a path mask generated in segment.gd. Because the
// trail is part of the terrain itself (no separate overlay mesh), it can never
// be drawn over the hero's sprite or tint its feet.

uniform sampler2D ground_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 ground_tint : source_color = vec4(0.80, 0.88, 0.76, 1.0);
uniform vec4 dirt_tint : source_color = vec4(0.94, 0.90, 0.82, 1.0);
uniform float uv_tiles = 9.0;
uniform float slope_shade = 0.34;
uniform float height_tint = 0.14;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 tiled_uv = UV * uv_tiles;
	vec3 grass = texture(ground_tex, tiled_uv).rgb * ground_tint.rgb;
	vec3 dirt = texture(dirt_tex, tiled_uv * 4.0 + vec2(0.17, 0.31)).rgb * dirt_tint.rgb;

	float mask = texture(path_mask, UV).r;
	// Per-pixel dissolve: the mask is smooth, the hash turns the rim into
	// clustered pixel specks instead of an alpha gradient (and stays opaque).
	float dither = hash(floor(world_pos.xz * 34.0));
	float trail = step(dither, mask);

	// Pixels right at the rim lean toward the grass colour, so the dirt reads as
	// thinning out even where a dirt pixel survives the dither.
	float rim = 1.0 - smoothstep(0.45, 0.80, mask);
	vec3 rim_dirt = mix(dirt, grass * vec3(0.66, 0.78, 0.52), rim * 0.60);

	vec3 ground_colour = mix(grass, rim_dirt, trail);

	// Read the relief: steep slopes darken (valley shadow) and high ground
	// catches a little more warm light.
	float slope = clamp(world_normal.y, 0.0, 1.0);
	ground_colour *= mix(1.0 - slope_shade, 1.0, slope);
	float height_mix = smoothstep(-4.0, 14.0, world_pos.y);
	ground_colour = mix(ground_colour * vec3(0.88, 0.94, 0.92),
		ground_colour * vec3(1.04, 1.01, 0.94), height_mix * height_tint * 4.0);

	ALBEDO = ground_colour;
	// A tiny self-lit floor keeps the far side of steep hills from reading as
	// pitch-black holes in night segments.
	EMISSION = ground_colour * 0.055;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
