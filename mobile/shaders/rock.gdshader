// Scattered boulders / shore rocks (Blender meshes, assets/models/*rock*.glb).
// Base colour comes from the baked vertex colours (cavity, minerals, moss or
// algae); a triplanar sample of the shared terrain detail texture adds grain,
// and rock below / near the waterline is darkened and glossier (wet).
shader_type spatial;

uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	float rk = texture(detail_tex, wpos.zy * 0.45).b * bw.x
		+ texture(detail_tex, wpos.xz * 0.45).b * bw.y
		+ texture(detail_tex, wpos.xy * 0.45).b * bw.z;
	vec3 col = COLOR.rgb * 1.9 * (0.8 + rk * 0.4);
	float wet = smoothstep(0.35, -0.05, wpos.y);
	col *= 1.0 - wet * 0.2;
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.35, wet);
	SPECULAR = mix(0.3, 0.6, wet);
}
