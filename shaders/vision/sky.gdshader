shader_type sky;
// Late-afternoon / Ghibli-ish sky for the post-ending vision.
// Three palettes are blended from the JavaScript-side time uniform:
//   0.0 = clear daytime, 0.55 = golden hour, 1.0 = purple-pink sunset.

uniform vec3 top_color : source_color = vec3(0.24, 0.55, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.86, 0.88);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.72);
uniform vec3 cloud_dark : source_color = vec3(0.62, 0.66, 0.72);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 sun_direction = vec3(0.2, 0.7, -0.3);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_scale : hint_range(0.2, 8.0) = 2.6;
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.018;
uniform float cloud_offset = 0.0;
uniform float sky_energy = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(11.7, 7.1);
		amplitude *= 0.48;
	}
	return value;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float height = clamp(dir.y, 0.0, 1.0);
	vec3 color = mix(horizon_color, top_color, pow(height, 0.45));

	// Sun glow and a small disc. The disc is intentionally soft, like a
	// hand-painted background rather than a physically perfect star.
	float sun_dot = clamp(dot(dir, normalize(sun_direction)), 0.0, 1.0);
	color += sun_color * pow(sun_dot, 8.0) * 0.16;
	color += sun_color * pow(sun_dot, 180.0) * 1.15;

	// Clouds are projected onto a virtual plane above the camera. They thicken
	// near the horizon and fade overhead, which reads as a low sunset cloud bank.
	vec2 cloud_uv = dir.xz / max(dir.y + 0.18, 0.06);
	cloud_uv = cloud_uv * cloud_scale + vec2(TIME * cloud_speed + cloud_offset, cloud_offset * 0.3);
	float shape = fbm(cloud_uv);
	float detail = fbm(cloud_uv * 2.3 + 31.0);
	float cloud = smoothstep(0.58 - cloud_cover * 0.42, 0.82 - cloud_cover * 0.14, shape * 0.72 + detail * 0.28);
	cloud *= smoothstep(-0.02, 0.20, dir.y);
	cloud *= 1.0 - smoothstep(0.55, 0.96, dir.y);
	float lit = pow(clamp(sun_dot, 0.0, 1.0), 3.0);
	vec3 cloud_color = mix(cloud_dark, cloud_light, lit * 0.72 + detail * 0.20);
	color = mix(color, cloud_color, cloud * 0.86);

	// A faint pink/violet band just above the horizon at sunset.
	float band = exp(-pow((dir.y - 0.06) * 7.0, 2.0));
	color = mix(color, horizon_color * 1.08, band * 0.22);
	color *= sky_energy;
	COLOR = color;

	// Keep the sky itself bright; the environment tonemap handles exposure.
}
