// Terrain ground material (GL Compatibility friendly: a handful of texture
// fetches, no texture arrays). Materials are blended per pixel from world
// height, surface slope, moisture and fertility, broken up by original
// tileable detail textures (tools/make_terrain_textures.py), so borders are
// soft and irregular and every edit / newly created island is shaded the same.
// The colour bands mirror the gameplay biomes in terrain.gd::_biome().
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D macro_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 mf;   // moisture, fertility

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	mf = UV;
}

void fragment() {
	vec2 p = wpos.xz;
	float h = wpos.y;
	vec3 n = normalize(wnrm);
	float steep = 1.0 - n.y;                 // 0 flat, ~0.4 at 53 degrees
	float m = mf.x;
	float fe = mf.y;

	vec4 d1 = texture(detail_tex, p * 0.31);
	vec4 d2 = texture(detail_tex, p * 0.067 + vec2(0.37, 0.11));
	vec4 mac = texture(macro_tex, p / 150.0);
	vec4 mac2 = texture(macro_tex, p / 47.0 + vec2(0.5, 0.21));
	float breakup = (d2.g - 0.5) + (mac2.a - 0.5) * 0.6;

	// ---- meadow grass: lush <-> mid by moisture, with dry patches and clumps
	vec3 g_lush = lin(vec3(0.33, 0.50, 0.19));
	vec3 g_mid = lin(vec3(0.44, 0.57, 0.24));
	vec3 g_dry = lin(vec3(0.66, 0.62, 0.36));
	vec3 g_forest = lin(vec3(0.27, 0.39, 0.17));
	vec3 soil = lin(vec3(0.46, 0.40, 0.30));
	vec3 col = mix(g_mid, g_lush, smoothstep(0.38, 0.7, m + breakup * 0.15));
	float dry = clamp(smoothstep(0.42, 0.22, m) + (mac.r - 0.55) * 1.3 + (d2.g - 0.5) * 0.4, 0.0, 1.0);
	col = mix(col, g_dry, dry * 0.6);
	float forest = smoothstep(0.56, 0.72, m + breakup * 0.08);
	col = mix(col, mix(g_forest, soil, 0.25 + d2.g * 0.25), forest * 0.85);
	// bare soil patches (more on drier ground and in forests)
	float dirt = smoothstep(0.70, 0.90, mac.g * 0.75 + d2.g * 0.35 + forest * 0.08 + dry * 0.05);
	col = mix(col, soil * (0.85 + d1.r * 0.3), dirt * 0.6);
	// fine grain / tufts and mid-scale clumps
	col *= 0.80 + d1.r * 0.34;
	col *= 0.90 + d2.g * 0.2;
	col *= 0.92 + mac.a * 0.16;
	// sparse wildflowers in open meadows
	float meadow = (1.0 - forest) * (1.0 - dry * 0.6) * (1.0 - dirt);
	float fl = step(0.82, d1.r) * mac2.b * meadow;
	col = mix(col, mix(lin(vec3(0.93, 0.86, 0.42)), lin(vec3(0.92, 0.92, 0.88)), step(0.5, d2.r)), clamp(fl * 1.5, 0.0, 0.7));

	// ---- alpine meadow then scree with height
	vec3 alpine = lin(vec3(0.50, 0.53, 0.33)) * (0.85 + d1.r * 0.3);
	col = mix(col, alpine, smoothstep(7.5, 10.5, h + breakup * 2.0));

	// ---- rock: triplanar, on steep slopes and high ground
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	float rk = texture(detail_tex, wpos.zy * 0.11).b * bw.x
		+ texture(detail_tex, wpos.xz * 0.11).b * bw.y
		+ texture(detail_tex, wpos.xy * 0.11).b * bw.z;
	float rk2 = texture(detail_tex, wpos.zy * 0.027 + 0.5).b * bw.x
		+ texture(detail_tex, wpos.xz * 0.027 + 0.5).b * bw.y
		+ texture(detail_tex, wpos.xy * 0.027 + 0.5).b * bw.z;
	vec3 rock = mix(lin(vec3(0.40, 0.39, 0.37)), lin(vec3(0.70, 0.68, 0.63)), rk * 0.6 + rk2 * 0.4);
	rock = mix(rock, rock * lin(vec3(1.05, 0.99, 0.90)), mac.a);           // warm / cool rock tones
	rock *= 0.8 + smoothstep(0.15, 0.45, rk) * 0.25;                     // dark cracks
	float rock_w = smoothstep(0.26, 0.40, steep + (rk - 0.5) * 0.14 + breakup * 0.05);
	float scree = smoothstep(12.5, 16.0, h + breakup * 3.0 + (rk - 0.5) * 2.0);
	rock_w = max(rock_w, scree * (0.55 + 0.45 * smoothstep(0.35, 0.65, rk2)));
	// moss / grass clinging to the less steep parts of rock
	vec3 mossy = mix(rock, col, 0.3 * (1.0 - smoothstep(0.3, 0.48, steep)) * (1.0 - scree));
	col = mix(col, mossy, rock_w);

	// ---- small snow caps on the highest, gentler ground
	float snow = smoothstep(19.0, 23.0, h + breakup * 4.0) * smoothstep(0.45, 0.25, steep);
	col = mix(col, lin(vec3(0.90, 0.92, 0.95)) * (0.92 + d1.a * 0.08), snow);

	// ---- fertility: blessed land is lusher, scorched land blackened
	float soft = (1.0 - rock_w) * (1.0 - snow);
	col = mix(col, lin(vec3(0.24, 0.52, 0.17)) * (0.85 + d1.r * 0.3), clamp(fe, 0.0, 1.0) * 0.5 * soft);
	col = mix(col, lin(vec3(0.12, 0.10, 0.08)) * (0.8 + d1.r * 0.4), clamp(-fe, 0.0, 1.0) * 0.9);

	// ---- beach: irregular sand band, wet sand at the waterline, sea bed below
	float shore = h + (d2.g - 0.5) * 0.5 + (mac.g - 0.5) * 0.5;
	vec3 sand = lin(vec3(0.84, 0.77, 0.58)) * (0.9 + d1.a * 0.14);
	vec3 wet = lin(vec3(0.62, 0.54, 0.40)) * (0.9 + d1.a * 0.1);
	sand = mix(sand, wet, smoothstep(0.35, 0.02, h));
	float beach_w = (1.0 - smoothstep(0.55, 1.15, shore)) * (1.0 - smoothstep(0.3, 0.5, steep));
	col = mix(col, sand, beach_w);
	// below the waterline: sand fading to a dark, slightly green sea bed
	vec3 bed = mix(wet, lin(vec3(0.30, 0.40, 0.33)), smoothstep(-0.5, -4.0, h));
	bed = mix(bed, lin(vec3(0.12, 0.22, 0.24)), smoothstep(-4.0, -11.0, h));
	col = mix(col, bed * (0.9 + d1.a * 0.12), smoothstep(0.0, -0.4, h));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, smoothstep(0.3, 0.0, h) * (1.0 - smoothstep(0.0, -0.5, h)));
	SPECULAR = 0.25;
}
