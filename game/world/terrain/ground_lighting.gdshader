shader_type canvas_item;

// Depth below the lights, used only for this floor's normal-map lighting.
uniform float lighting_depth : hint_range(0.0, 512.0, 1.0) = 160.0;

void fragment() {
	LIGHT_VERTEX.z = -lighting_depth;
}
