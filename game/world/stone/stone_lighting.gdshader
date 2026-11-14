shader_type canvas_item;

uniform sampler2D silhouette_texture : filter_nearest, repeat_disable;
uniform int open_sides = 0;
uniform float crack_accent = 0.0;

uniform sampler2D light_projection : filter_nearest, repeat_disable;
uniform bool projection_enabled = false;
varying vec4 projected_source_a;
varying vec4 projected_source_b;
varying vec4 projection_metadata;

varying vec2 canvas_right;
varying vec2 canvas_down;

void vertex() {
	mat4 local_to_canvas = CANVAS_MATRIX * MODEL_MATRIX;
	canvas_right = local_to_canvas[0].xy;
	canvas_down = local_to_canvas[1].xy;
	projected_source_a = vec4(0.0);
	projected_source_b = vec4(0.0);
	projection_metadata = vec4(0.0);
	if (projection_enabled) {
		vec4 a = textureLod(light_projection, vec2(0.25, 0.25), 0.0);
		vec4 b = textureLod(light_projection, vec2(0.75, 0.25), 0.0);
		vec2 a_meta = textureLod(light_projection, vec2(0.25, 0.75), 0.0).rg;
		vec2 b_meta = textureLod(light_projection, vec2(0.75, 0.75), 0.0).rg;
		projected_source_a = vec4((CANVAS_MATRIX * vec4(a.xy, 0.0, 1.0)).xy,
				(CANVAS_MATRIX * vec4(a.zw, 0.0, 1.0)).xy);
		projected_source_b = vec4((CANVAS_MATRIX * vec4(b.xy, 0.0, 1.0)).xy,
				(CANVAS_MATRIX * vec4(b.zw, 0.0, 1.0)).xy);
		float canvas_scale = (length(CANVAS_MATRIX[0].xy) + length(CANVAS_MATRIX[1].xy)) * 0.5;
		projection_metadata = vec4(a_meta.x * canvas_scale, b_meta.x * canvas_scale, a_meta.y, b_meta.y);
	}
}

void fragment() {
	vec2 tile_size = REGION_RECT.zw / TEXTURE_PIXEL_SIZE;
	vec2 tile_pixel = (UV - REGION_RECT.xy) / TEXTURE_PIXEL_SIZE;
	float roof_height = tile_size.y * 0.5;
	const float edge_bias = 1.0;
	bool front = tile_pixel.y >= roof_height;
	int exposed = front ? open_sides >> 2 : open_sides;
	if ((exposed & 3) != 0) {
		vec2 cut = texture(silhouette_texture, tile_pixel / tile_size).rg;
		if (((exposed & 1) != 0 && cut.r > 0.5) || ((exposed & 2) != 0 && cut.g > 0.5)) {
			discard;
		}
	}
	if (front && (open_sides & 48) != 0) {
		float contact = 0.0;
		if ((open_sides & 16) != 0) {
			contact = 1.0 - smoothstep(0.0, 11.0, tile_pixel.x);
		}
		if ((open_sides & 32) != 0) {
			contact = max(contact, 1.0 - smoothstep(0.0, 11.0, tile_size.x - tile_pixel.x));
		}
		float front_depth = (tile_pixel.y - roof_height) / roof_height;
		COLOR.rgb *= 1.0 - 0.34 * contact * smoothstep(0.0, 0.3, front_depth);
	}

	// Damage grooves affect surface lighting. Use the intact atlas row for the shadow projection.
	const float atlas_rows = 6.0;
	float atlas_row = floor(REGION_RECT.y * atlas_rows + 0.0001);
	float damage_stage = mod(atlas_row, 3.0);
	vec2 intact_uv = UV - vec2(0.0, damage_stage / atlas_rows);
	vec2 intact_normal = texture(NORMAL_TEXTURE, intact_uv).rg;
	if (damage_stage > 0.0) {
		vec4 damaged_normal = texture(NORMAL_TEXTURE, UV);
		// Alpha preserves the dark floor of the groove while the new rim catches the pulse.
		COLOR.rgb *= damaged_normal.a;
		if (crack_accent > 0.0) {
			vec2 previous_normal = intact_normal;
			if (damage_stage > 1.0) {
				previous_normal = texture(NORMAL_TEXTURE, UV - vec2(0.0, 1.0 / atlas_rows)).rg;
			}
			float rim_mask = smoothstep(0.025, 0.075, length(damaged_normal.rg - intact_normal));
			float new_mask = smoothstep(0.025, 0.075, length(damaged_normal.rg - previous_normal));
			float accent = crack_accent * rim_mask * new_mask * step(0.99, damaged_normal.a);
			COLOR.rgb *= vec3(1.0) + accent * vec3(1.0, 0.84, 0.68);
		}
	}
	vec2 rim = intact_normal * 2.0 - 1.0;
	if (abs(rim.x) > max(abs(rim.y), 0.03)) {
		float outside_x = rim.x < 0.0 ? -edge_bias : tile_size.x + edge_bias;
		SHADOW_VERTEX += canvas_right * (outside_x - tile_pixel.x);
		float side_depth = front ? tile_size.y - tile_pixel.y : roof_height;
		SHADOW_VERTEX += canvas_down * side_depth;
	} else if (front || abs(rim.y) > 0.03) {
		float outside_y = rim.y > 0.0 ? roof_height - edge_bias : tile_size.y + edge_bias;
		SHADOW_VERTEX += canvas_down * (outside_y - tile_pixel.y);
	} else {
		SHADOW_VERTEX += canvas_down * roof_height;
	}
}


void light() {
	vec3 direction = LIGHT_DIRECTION;
	if (projection_enabled && !LIGHT_IS_DIRECTIONAL) {
		vec2 origin = LIGHT_POSITION.xy;
		vec2 delta_a = origin - projected_source_a.xy;
		vec2 delta_b = origin - projected_source_b.xy;
		if (projection_metadata.z > 0.5 && dot(delta_a, delta_a) < 0.25
				&& abs(LIGHT_POSITION.z - projection_metadata.x) < 0.01) {
			origin = projected_source_a.zw;
		} else if (projection_metadata.w > 0.5 && dot(delta_b, delta_b) < 0.25
				&& abs(LIGHT_POSITION.z - projection_metadata.y) < 0.01) {
			origin = projected_source_b.zw;
		}
		direction = normalize(vec3(origin, LIGHT_POSITION.z) - LIGHT_VERTEX);
	}
	// Same diffuse normal-map response as the engine; native shadows remain independent.
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY
			* max(0.0, dot(NORMAL, direction)), LIGHT_COLOR.a);
}
