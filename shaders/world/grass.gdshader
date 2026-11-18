shader_type spatial;
// HD2D grass blade shader.
//
// A single vertical quad per blade. Wind sway is computed in the vertex stage
// from TIME + the instance world origin (phase) + a per-blade INSTANCE_CUSTOM.x
// random phase. The sway grows with the square of the height fraction so the
// base stays rooted. Normals are blended towards +Y so the flat quads light
// softly like a grass canopy instead of like little cardboard cut-outs.
//
// The optional blade texture (res://assets/generated/grass_blade.png) is used
// for the alpha cutout only; colour comes from the base->tip gradient below so
// the field stays coherent even if the art file is missing (hint_default_white
// makes the sampler return opaque white when unassigned).
//
// render_mode cull_disabled : quads are single sided, both sides must draw.
// The blade does NOT cast shadows; that is set on the MultiMeshInstance3D.

render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

// --- colour -----------------------------------------------------------------
uniform vec4 base_color : source_color = vec4(0.10, 0.21, 0.07, 1.0);
uniform vec4 tip_color : source_color = vec4(0.46, 0.69, 0.26, 1.0);
uniform vec4 dry_color : source_color = vec4(0.58, 0.52, 0.24, 1.0);
uniform float dry_mix : hint_range(0.0, 1.0) = 0.10;

// --- geometry / warp --------------------------------------------------------
// Height of the quad in mesh units (VERTEX.y is -h/2..+h/2). Used to derive a
// texture-UV-independent "tip factor", so panel UVs cannot break the sway.
uniform float blade_height : hint_range(0.01, 4.0) = 0.42;

// --- wind -------------------------------------------------------------------
uniform float wind_strength : hint_range(0.0, 0.5) = 0.085;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.7;
uniform vec2 wind_direction = vec2(0.86, 0.5);

// --- alpha cutout -----------------------------------------------------------
uniform sampler2D blade_tex : source_color, hint_default_white, filter_linear, repeat_disable;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.42;

// --- character trampling ----------------------------------------------------
// The segment feeds the hero's world position / velocity every frame. Blades
// near the feet bend away and slightly down, so walking through the field
// parts the grass around the character.
uniform vec3 player_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 player_vel = vec3(0.0);
uniform float trample_radius : hint_range(0.1, 3.0) = 1.35;
uniform float trample_strength : hint_range(0.0, 2.0) = 0.85;

varying float v_tip;
varying float v_tint;

void vertex() {
	// 0 at the ground, 1 at the blade tip (independent of mesh UVs).
	float tip = clamp(VERTEX.y / blade_height + 0.5, 0.0, 1.0);
	v_tip = tip;
	v_tint = INSTANCE_CUSTOM.y;

	// Wind direction is authored in world space; bring it into the blade's local
	// space so every blade leans the same way even though each has a random yaw.
	vec3 wind_world = normalize(vec3(wind_direction.x, 0.0, wind_direction.y));
	vec3 basis_x = MODEL_MATRIX[0].xyz;
	vec3 basis_z = MODEL_MATRIX[2].xyz;
	vec3 local_wind = vec3(dot(basis_x, wind_world), 0.0, dot(basis_z, wind_world));
	float local_len = length(local_wind);
	if (local_len > 0.0001) {
		local_wind /= local_len;
	} else {
		local_wind = vec3(0.0, 0.0, 1.0);
	}

	vec3 world_origin = MODEL_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831853;

	// A slow travelling gust plus a faster per-blade flutter.
	float gust = sin(TIME * 0.45 + world_origin.x * 0.055 + world_origin.z * 0.040) * 0.5 + 0.5;
	float sway = sin(TIME * wind_speed + phase + world_origin.x * 0.19 + world_origin.z * 0.16) * 0.62
			+ sin(TIME * wind_speed * 2.3 + phase * 1.7 + world_origin.z * 0.36) * 0.38;

	float bend = tip * tip;
	float amount = wind_strength * (0.5 + 0.9 * gust) * sway * bend;
	VERTEX += local_wind * amount;
	// Slight downward arc so the tip does not stretch while it bends.
	VERTEX.y -= abs(amount) * 0.30;

	// --- trampling ---------------------------------------------------------
	vec3 player_delta = world_origin - player_pos;
	float distance_to_player = length(player_delta.xz);
	float influence = 1.0 - smoothstep(0.0, trample_radius, distance_to_player);
	if (influence > 0.001) {
		vec3 push_world = normalize(vec3(player_delta.x, 0.0, player_delta.z) + vec3(0.0001, 0.0, 0.0));
		// Bring the push direction into the blade's local frame.
		vec3 local_push = vec3(dot(basis_x, push_world), 0.0, dot(basis_z, push_world));
		float push_len = length(local_push);
		if (push_len > 0.0001) {
			local_push /= push_len;
		} else {
			local_push = vec3(0.0, 0.0, 1.0);
		}
		float speed_factor = clamp(0.55 + length(player_vel.xz) * 0.55, 0.55, 1.5);
		float trample = trample_strength * influence * speed_factor * tip * tip;
		// A little per-blade resistance so the field does not dent like a sheet.
		trample *= 0.75 + 0.35 * INSTANCE_CUSTOM.x;
		VERTEX += local_push * trample;
		VERTEX.y -= trample * 0.50;
	}

	// Soft, upward-biased normal for gentle lighting on the thin quads.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
}

void fragment() {
	// Map the geometric tip to the top of the texture regardless of PlaneMesh UV
	// orientation (v = 0 is the top row of a Godot texture).
	vec2 blade_uv = vec2(UV.x, 1.0 - v_tip);
	vec4 tex = texture(blade_tex, blade_uv);

	vec3 col = mix(base_color.rgb, tip_color.rgb, v_tip * v_tip * 0.6 + v_tip * 0.4);
	col = mix(col, dry_color.rgb, v_tint * dry_mix);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
}
