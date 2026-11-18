shader_type canvas_item;
// Liquid inside the heart-shaped glass charm: the base colour is the current
// mixture, and a newly taken colour swirls in when mix_amount rises.
render_mode blend_mix;

uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform vec4 base_color : source_color = vec4(0.97, 0.96, 0.93, 1.0);
uniform vec4 incoming_color : source_color = vec4(0.97, 0.96, 0.93, 1.0);
uniform float mix_amount : hint_range(0.0, 1.0) = 0.0;
uniform float liquid_time : hint_range(0.0, 1000.0) = 0.0;
uniform float liquid_alpha : hint_range(0.0, 1.0) = 0.92;
uniform float swirl_amount : hint_range(0.0, 2.0) = 1.0;
// The glass holds still; the liquid inside sloshes when the hero walks.
uniform vec2 slosh_dir = vec2(0.0);
uniform float slosh_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wave_time = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	float mask = texture(mask_tex, UV).r;
	if (mask < 0.5) {
		discard;
	}
	// The liquid only fills the lower part of the glass heart; the upper lobes
	// stay clear so the transparent container reads clearly.
	float slope = slosh_dir.x * 0.16 * slosh_strength;
	float ripple = sin(UV.x * 19.0 + wave_time * 5.0) * 0.030 * slosh_strength;
	float surface = 0.30
			+ 0.020 * sin(UV.x * 13.0 + liquid_time * 1.2)
			+ 0.012 * sin(UV.x * 27.0 - liquid_time * 0.9)
			+ slope * (UV.x - 0.5)
			+ ripple;
	if (UV.y < surface) {
		discard;
	}
	float surface_fade = smoothstep(surface, surface + 0.018, UV.y);
	vec2 p = UV - vec2(0.5, 0.52);
	float radius = length(p) * 2.0;
	float angle = atan(p.y, p.x);

	// A slow, liquid swirl that carries the incoming colour through the base.
	float swirl = 0.5 + 0.5 * sin(angle * 2.6 + liquid_time * 1.6 + radius * 5.5);
	float front = mix_amount * (0.52 + 0.48 * swirl);
	front += mix_amount * 0.22 * (1.0 - smoothstep(0.0, 0.55, radius));
	front = clamp(front * swirl_amount, 0.0, 1.0);

	vec3 colour = mix(base_color.rgb, incoming_color.rgb, front);

	// Suspended "liquid sand": dense fine flecks, darker grit and soft cloudy
	// veils slowly rotating with the liquid. This is what gives the charm its
	// grainy, sandy swirl instead of a clean flat liquid.
	vec2 sand_p = UV - vec2(0.5, 0.45);
	float sand_angle = liquid_time * 0.18 + sand_p.y * 1.2;
	mat2 sand_rot = mat2(
		vec2(cos(sand_angle), -sin(sand_angle)),
		vec2(sin(sand_angle), cos(sand_angle))
	);
	vec2 sand_uv = sand_rot * sand_p * 54.0
			+ vec2(liquid_time * 0.8, -liquid_time * 0.45)
			+ slosh_dir * (9.0 * slosh_strength);
	float grain = hash21(floor(sand_uv));
	float grain2 = hash21(floor(sand_uv * 1.9 + 31.7));
	float cloud = fbm(sand_p * 9.0 + vec2(liquid_time * 0.05, -liquid_time * 0.04) + slosh_dir * (0.35 * slosh_strength));
	float fine = smoothstep(0.35, 0.95, grain) * 0.22;
	float sparkle = pow(grain2, 14.0) * 0.65 * (0.75 + 0.9 * slosh_strength);
	colour = mix(colour, vec3(1.0), fine + sparkle * 0.35);
	colour = mix(colour, colour * 0.58, pow(1.0 - grain, 10.0) * 0.35);
	colour += (grain2 - 0.5) * 0.05;
	colour = mix(colour, colour * 1.12 + 0.025, cloud * 0.35);

	// Liquid depth: a little darker towards the bottom tip, glassy sheen at the
	// upper-left, and a faint pearly centre.
	float depth = smoothstep(0.55, 1.15, UV.y);
	colour *= 1.0 - depth * 0.14;
	float sheen = smoothstep(0.34, 0.0, distance(UV, vec2(0.36, 0.30)));
	colour = mix(colour, vec3(1.0), sheen * 0.14);
	float pearl = smoothstep(0.50, 0.0, distance(UV, vec2(0.56, 0.48)));
	colour = mix(colour, vec3(1.0), pearl * 0.05);

	COLOR = vec4(colour, liquid_alpha * surface_fade);
}
