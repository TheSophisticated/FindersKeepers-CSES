shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = true;
uniform vec4 base_albedo_color : source_color = vec4(1.0);
uniform vec3 target_tint : source_color = vec3(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.9;
uniform bool is_hair = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec4 sampled = has_albedo_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 orig = sampled.rgb * base_albedo_color.rgb;
	float alpha = sampled.a;

	if (is_hair) {
		if (alpha < alpha_scissor_threshold) {
			discard;
		}
		float lum = dot(orig, vec3(0.299, 0.587, 0.114));
		float rel_lum = clamp(pow(max(lum, 0.03) / 0.32, 0.62), 0.38, 1.55);
		vec3 recolored = target_tint * rel_lum;
		ALBEDO = mix(orig, recolored, tint_strength);
		ROUGHNESS = clamp(roughness_val, 0.45, 0.9);
	} else {
		float lum = dot(orig, vec3(0.299, 0.587, 0.114));
		float cmax = max(orig.r, max(orig.g, orig.b));
		float cmin = min(orig.r, min(orig.g, orig.b));
		float sat = cmax - cmin;
		// Preserve dark eye pupils/lashes and bright neutral sclera whites
		float not_pupil = smoothstep(0.05, 0.18, lum);
		float is_sclera = smoothstep(0.76, 0.90, lum) * (1.0 - smoothstep(0.02, 0.13, sat));
		float skin_mask = clamp(not_pupil * (1.0 - is_sclera), 0.0, 1.0);
		float rel_lum = clamp(pow(max(lum, 0.04) / 0.52, 0.68), 0.36, 1.32);
		vec3 recolored = target_tint * rel_lum;
		ALBEDO = mix(orig, recolored, tint_strength * skin_mask);
		ROUGHNESS = clamp(roughness_val, 0.52, 0.85);
	}
	METALLIC = 0.0;
}
