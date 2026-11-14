shader_type canvas_item;

uniform sampler2D robot_diffuse : source_color, filter_nearest, repeat_disable;
uniform sampler2D robot_normal : filter_nearest, repeat_disable;

uniform float eye_power = 1.0;
uniform vec2 damage_origin = vec2(0.0);
uniform float damage_radius = 12.0;
uniform float damage_pulse = 0.0;

uniform vec2 hit_origin = vec2(0.0);
uniform vec2 hit_displacement = vec2(0.0);
uniform float hit_radius = 20.0;
uniform float hit_body_bottom = 0.0;

varying vec2 local_pixel;
varying vec4 vertex_tint;

bool is_visor(vec3 color) {
	return color.r > 0.95 && max(color.g, color.b) < 0.06;
}

void vertex() {
	local_pixel = VERTEX;
	vertex_tint = COLOR;
}

void fragment() {
	COLOR = vertex_tint * texture(robot_diffuse, UV);
	vec2 facing = sign(REGION_RECT.zw);
	vec2 normal_uv = UV;
	if (dot(hit_displacement, hit_displacement) >= 0.25 && local_pixel.y < hit_body_bottom
			&& !is_visor(COLOR.rgb)) {
		vec2 pixel = floor(local_pixel) + vec2(0.5);
		vec2 inward = normalize(hit_displacement);
		vec2 across = vec2(-inward.y, inward.x);
		float across_hit = abs(dot(pixel - hit_origin, across));
		float band = 1.0 - smoothstep(hit_radius * 0.3, hit_radius, across_hit);
		// Anchor the far side and spread the compression along the struck side.
		vec2 body_center = vec2(0.0, hit_body_bottom - hit_radius * 0.85);
		float struck_side = dot(pixel - body_center, -inward);
		float side = smoothstep(-4.0, hit_radius * 0.42, struck_side);
		float armor = 1.0 - smoothstep(hit_body_bottom - 5.0, hit_body_bottom, pixel.y);
		vec2 shift = round(hit_displacement * band * side * armor);
		if (dot(shift, shift) > 0.0 && pixel.y - shift.y < hit_body_bottom) {
			// Atlas regions can have a signed size when the sprite is mirrored.
			vec2 texel_half = TEXTURE_PIXEL_SIZE * 0.5;
			vec2 sample_uv = clamp(UV - shift * TEXTURE_PIXEL_SIZE * facing,
					REGION_RECT.xy + texel_half, REGION_RECT.xy + abs(REGION_RECT.zw) - texel_half);
			vec4 surface = texture(robot_diffuse, sample_uv);
			if (!is_visor(surface.rgb)) {
				COLOR = vertex_tint * surface;
				normal_uv = sample_uv;
			}
		}
	}
	vec2 normal_xy = (texture(robot_normal, normal_uv).rg * vec2(2.0, -2.0)
			- vec2(1.0, -1.0)) * facing;
	NORMAL = vec3(normal_xy, sqrt(max(0.0, 1.0 - dot(normal_xy, normal_xy))));
	if (COLOR.a == 0.0) {
		discard;
	}
	if (is_visor(COLOR.rgb)) {
		COLOR.rgb = mix(vec3(0.082, 0.075, 0.165), COLOR.rgb, eye_power);
	} else if (damage_pulse > 0.0) {
		float distance_to_break = length(floor(local_pixel) - floor(damage_origin));
		float glow = 1.0 - smoothstep(1.0, damage_radius, distance_to_break);
		float metal = smoothstep(0.09, 0.48, COLOR.b);
		COLOR.rgb += vec3(0.20, 0.64, 0.88) * glow * damage_pulse * metal;
	}
	LIGHT_VERTEX.z -= 18.0;
}
