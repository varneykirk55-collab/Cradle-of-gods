// Sea surface. Depth comes from the live terrain heightmap (Terrain.height_tex,
// refreshed with the collider after every edit), so every coastline -- the
// generated island and any land the player raises or removes -- gets the same
// clear turquoise shallows, green-blue shelf, deep blue water and a soft,
// breaking foam line. Compatibility renderer friendly: no screen/depth
// texture reads, two normal-map fetches for the ripples.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D wave_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap;
uniform float half_size = 112.0;
uniform float sea = 0.0;
uniform vec4 shallow : source_color = vec4(0.38, 0.80, 0.74, 1.0);
uniform vec4 shelf : source_color = vec4(0.13, 0.55, 0.60, 1.0);
uniform vec4 deep : source_color = vec4(0.05, 0.22, 0.40, 1.0);
uniform vec4 horizon : source_color = vec4(0.62, 0.74, 0.84, 1.0);

varying vec3 wpos;

float ground(vec2 p) {
	vec2 uv = (p + vec2(half_size) + 0.5) / (half_size * 2.0 + 1.0);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return -14.0;
	return texture(height_tex, uv).r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.21 + TIME * 0.8) * 0.035 + cos(wpos.z * 0.17 + TIME * 0.6) * 0.035;
}

void fragment() {
	float depth = max(sea - ground(wpos.xz), 0.0);
	// colour by depth: absorption-like falloff
	vec3 col = mix(shallow.rgb, shelf.rgb, 1.0 - exp(-depth * 0.55));
	col = mix(col, deep.rgb, 1.0 - exp(-max(depth - 2.0, 0.0) * 0.22));
	// ripples
	vec2 uv1 = wpos.xz * 0.045 + vec2(TIME * 0.012, TIME * 0.007);
	vec2 uv2 = wpos.xz * 0.11 + vec2(-TIME * 0.016, TIME * 0.011);
	vec3 n1 = texture(wave_normal, uv1).xyz;
	vec3 n2 = texture(wave_normal, uv2).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	// shore foam: a thin band at the waterline plus slow wash lines that run in
	float g = texture(detail_tex, wpos.xz * 0.2 + vec2(TIME * 0.01, 0.0)).g;
	float band = smoothstep(0.32, 0.02, depth);
	float wash = smoothstep(0.75, 1.0, sin(depth * 9.0 - TIME * 1.3 + g * 3.0)) * smoothstep(1.4, 0.25, depth);
	float foam = clamp(band * (0.55 + g * 0.6) + wash * 0.45 * g, 0.0, 1.0);
	// distant water blends toward the sky horizon (hides the plane edge)
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float haze = smoothstep(260.0, 620.0, dist);
	col = mix(col, horizon.rgb, haze * 0.85);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(col, vec3(0.95, 0.97, 0.97), foam);
	// clear shallows show the sand, deep water is nearly opaque
	ALPHA = clamp(mix(0.30, 0.94, 1.0 - exp(-depth * 0.7)) + fres * 0.25 + foam * 0.6 + haze, 0.0, 0.97);
	ROUGHNESS = mix(0.08, 0.6, foam);
	SPECULAR = 0.55;
}
