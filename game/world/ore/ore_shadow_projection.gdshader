shader_type canvas_item;

uniform vec2 ground_anchor = vec2(0.0, 16.0);
varying vec2 ground_canvas;

void vertex() {
	ground_canvas = (CANVAS_MATRIX * MODEL_MATRIX * vec4(ground_anchor, 0.0, 1.0)).xy;
}

void fragment() {
	NORMAL_MAP = texture(NORMAL_TEXTURE, UV).rgb;
	SHADOW_VERTEX = ground_canvas;
}
