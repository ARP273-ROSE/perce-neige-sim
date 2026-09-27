// Passagers et matériel en MultiMesh : un seul maillage, plusieurs couleurs
// par pièce. Les couleurs de SOMMET sont des masques (R veste / skis / surf,
// G pantalon, B casque, alpha 0 = peau, noir = bottes, gants, fixations) ;
// la couleur de la veste vient de INSTANCE_CUSTOM, pantalon et casque
// d'une palette indexée par INSTANCE_ID — chaque silhouette est différente
// sans données supplémentaires (retour d'essai 2026-09-27 : « le design
// est ultra basique »).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

varying vec3 v_albedo;

const vec3 PANTS[6] = vec3[6](
	vec3(0.12, 0.12, 0.14), vec3(0.20, 0.22, 0.32), vec3(0.36, 0.10, 0.10),
	vec3(0.15, 0.26, 0.20), vec3(0.30, 0.30, 0.33), vec3(0.55, 0.45, 0.20));
const vec3 HELM[5] = vec3[5](
	vec3(0.10, 0.10, 0.11), vec3(0.92, 0.92, 0.90), vec3(0.55, 0.12, 0.10),
	vec3(0.20, 0.30, 0.60), vec3(0.85, 0.55, 0.10));

void vertex() {
	vec4 m = COLOR;
	vec3 custom = INSTANCE_CUSTOM.rgb;
	int id = int(INSTANCE_ID);
	vec3 pants = PANTS[id % 6];
	vec3 helm = HELM[(id / 6) % 5];
	vec3 skin = vec3(0.86, 0.70, 0.56);
	vec3 base = vec3(0.14, 0.14, 0.15);
	float w_base = clamp(1.0 - m.r - m.g - m.b, 0.0, 1.0);
	vec3 col = base * w_base + custom * m.r + pants * m.g + helm * m.b;
	v_albedo = mix(skin, col, m.a);
}

void fragment() {
	ALBEDO = v_albedo;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
