shader_type canvas_item;

uniform vec3 cut_normal = vec3(0.0, 0.0, 1.0);

void fragment() {
	NORMAL_MAP = vec3(vec2(0.5) + cut_normal.xy * vec2(0.5, -0.5), cut_normal.z);
}
