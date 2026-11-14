shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float edge_distance = length((UV - vec2(0.5)) * 2.0);
	float darkness = smoothstep(0.55, 1.05, edge_distance) * 0.95;
	COLOR = vec4(0.0, 0.0, 0.0, darkness);
}
