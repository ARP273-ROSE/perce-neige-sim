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

// Coupe du brin au fragment près : le câble n'existe qu'ENTRE la rame qu'il
// tire (attache culot, s = cut_below_s) et la poulie motrice en haut. Le
// masquage par segments entiers de 15 m laissait dépasser jusqu'à 15 m de
// câble DEVANT la cabine en descente (morceaux qui apparaissaient puis
// disparaissaient d'un coup au franchissement de chaque segment).
uniform float cut_below_s = 0.0;

// Rupture du câble (retour du 01/10/2026 : « il doit se détendre, casser
// quelque part ») — piloté par TrackBuilder.update_cable_rupture :
//   slack       0 tendu → 1 détendu : chaque sommet descend de UV2.x mètres
//               (posé sur la longrine entre les galets, calculé au build) ;
//   gap_lo/hi   brèche entre les deux bouts (abscisses en m), rien si
//               gap_hi <= gap_lo ;
//   phase_upper phase du tronçon resté sur les roues (figé, la machinerie
//               est arrêtée) — le tronçon bas suit sa rame (cable_phase).
uniform float slack = 0.0;
uniform float gap_lo = -1.0;
uniform float gap_hi = -1.0;
uniform float phase_upper = 0.0;

// Ondulation du câble lâche posé sur la longrine : il ne reste pas tiré au
// cordeau, il serpente doucement (amplitude et longueur d'onde en m).
uniform float slack_wave_amp = 0.035;
uniform float slack_wave_len = 7.3;

void vertex() {
	if (slack > 0.0) {
		vec3 down = normalize((inverse(MODEL_MATRIX) * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
		vec3 droite = COLOR.rgb * 2.0 - 1.0;
		float s = UV.y * uv_y_to_meters;
		float onde = sin(6.2831853 * s / slack_wave_len) * 0.7
			+ sin(6.2831853 * s / (slack_wave_len * 2.7) + 1.3) * 0.3;
		// près de la brèche, les bouts fouettés ont fait des boucles plus
		// larges (jusqu'à 10 cm, restent sur la longrine de 50 cm)
		float amp = slack_wave_amp;
		if (gap_hi > gap_lo) {
			float d_cut = min(abs(s - gap_lo), abs(s - gap_hi));
			amp += 0.065 * exp(-d_cut / 6.0);
		}
		VERTEX += down * (UV2.x * slack)
			+ droite * (amp * onde * UV2.y * slack);
	}
}

void fragment() {
	// Position géométrique (non animée) le long du câble, en mètres.
	float s_geom = UV.y * uv_y_to_meters;
	if (s_geom < cut_below_s) {
		discard;
	}
	bool broken = gap_hi > gap_lo;
	if (broken && s_geom > gap_lo && s_geom < gap_hi) {
		discard;
	}
	// Distance le long du câble en mètres, animée par cable_phase
	float ph = (broken && s_geom >= gap_hi) ? phase_upper : cable_phase;
	float s_meters = s_geom - ph;

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
	// Bouts rompus : fils d'acier à vif, clairs et brillants sur 25 cm
	if (broken) {
		float d_cut = min(abs(s_geom - gap_lo), abs(s_geom - gap_hi));
		float vif = 1.0 - smoothstep(0.05, 0.25, d_cut);
		ALBEDO = mix(ALBEDO, vec3(0.78, 0.78, 0.80), vif);
		ROUGHNESS = mix(ROUGHNESS, 0.15, vif);
	}

	// Léger effet d'ombrage du creux : les creux paraissent plus "sombres" en
	// ajoutant une touche d'emission légère sur les crêtes (effet spéculaire).
	EMISSION = vec3(lum * 0.025);
}
