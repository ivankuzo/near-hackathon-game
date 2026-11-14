shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float distance_from_center = length((UV - vec2(0.5)) * 2.0);
	float edge = smoothstep(0.35, 1.1, distance_from_center);
	COLOR = vec4(0.55, 0.04, 0.04, edge * 0.25) * COLOR;
}
