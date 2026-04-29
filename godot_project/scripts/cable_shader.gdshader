shader_type spatial;
render_mode specular_schlick_ggx, diffuse_lambert_wrap;

// Câble Fatzer 52 mm "6×26 fils Thermocompacte" : 6 torons principaux
// toronnés autour d'une âme centrale. Chaque toron fait un tour complet
// tous les ~400 mm (pitch d'hélice). Rendu procédural des bandes
// hélicoïdales, animées selon cable_phase pour donner le défilement
// correct en référentiel cabine.

uniform vec3 albedo_crest : source_color = vec3(0.38, 0.38, 0.42);   // crête du toron (éclairée)
uniform vec3 albedo_trough : source_color = vec3(0.08, 0.08, 0.10);  // creux entre torons (sombre)
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.95;

// Phase animée : offset accumulé en mètres le long du câble. Mis à jour par GDScript
// depuis l'extérieur — chaque brin a sa propre phase (opposée en signe).
uniform float cable_phase = 0.0;

// Paramètres géométriques du toronnage
uniform float strand_pitch = 0.45;   // 1 tour complet tous les 45 cm
uniform float n_strands = 6.0;        // 6 torons (Fatzer 6×26 fils)
uniform float trough_sharpness : hint_range(0.5, 8.0) = 2.2;  // netteté des creux

// Les segments de câble reçoivent UV.y en unités arbitraires proportionnelles
// à la distance le long du câble. Mon _build_cable_segment utilise
// v_uv = i * seg_len / n_steps / 0.5, donc UV.y ≈ 2 × (distance_en_m).
// Facteur de conversion UV → m :
uniform float uv_y_to_meters = 0.5;

void fragment() {
	// Distance le long du câble en mètres, animée par cable_phase
	float s_meters = UV.y * uv_y_to_meters - cable_phase;

	// Position angulaire le long de l'hélice : combinaison de l'angle autour du
	// câble (UV.x) et de la distance le long (s_meters). Chaque toron fait un
	// tour complet tous les strand_pitch mètres.
	float helix_phase = UV.x * n_strands - s_meters / strand_pitch * n_strands;
	float stripe = fract(helix_phase);

	// Courbe en creux : dark au bord (stripe proche de 0/1), clair au centre (0.5).
	// Utilise un profil cosinus puissance pour des creux nets.
	float sine = 0.5 - 0.5 * cos(stripe * 6.28318530718);
	float lum = pow(sine, 1.0 / trough_sharpness);

	ALBEDO = mix(albedo_trough, albedo_crest, lum);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;

	// Léger effet d'ombrage du creux : les creux paraissent plus "sombres" en
	// ajoutant une touche d'emission légère sur les crêtes (effet spéculaire).
	EMISSION = vec3(lum * 0.025);
}
