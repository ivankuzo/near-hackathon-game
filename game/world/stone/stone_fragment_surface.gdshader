shader_type canvas_item;

uniform sampler2D silhouette_texture : filter_nearest, repeat_disable;
uniform vec4 atlas_region;
uniform int open_sides = 0;

void fragment() {
	vec2 tile_uv = (UV / TEXTURE_PIXEL_SIZE - atlas_region.xy) / atlas_region.zw;
	int exposed = tile_uv.y < 0.5 ? open_sides : open_sides >> 2;
	vec2 cut = texture(silhouette_texture, tile_uv).rg;
	if (((exposed & 1) != 0 && cut.r > 0.5) || ((exposed & 2) != 0 && cut.g > 0.5)) {
		discard;
	}
	COLOR.rgb *= texture(NORMAL_TEXTURE, UV).a;
}
