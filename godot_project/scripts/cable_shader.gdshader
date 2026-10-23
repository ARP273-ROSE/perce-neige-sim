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
// Élasticité du brin (retour d'utilisateur, 11/10/2026 : « quand la rame du bas
// oscille, le mouvement du câble est le même jusqu'à la poulie motrice,
// alors qu'un élastique bouge d'autant plus qu'on est loin de l'accroche ») :
// la phase passe de cable_phase à l'attache de la rame (s_attache) à
// phase_poulie au sommet (s_poulie), linéairement. phase_poulie = cable_phase
// tant qu'elle n'est pas renseignée (effilement nul).
uniform bool effile = false;
uniform float phase_poulie = 0.0;
uniform float s_attache = 0.0;
uniform float s_poulie = 3514.52;

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

// Remontées mécaniques : flèche due au POIDS PONCTUEL de chaque véhicule
// (retour d'utilisateur, 23/10/2026). Câble tendu (tension horizontale H)
// entre deux appuis x1 < x2 : une charge P en a l'abaisse de
// (P/H)·(x−x1)(x2−a)/(x2−x1) avant a, symétriquement après. On retranche la
// charge moyenne répartie (w/H)·(x−x1)(x2−x)/2, déjà dans la chaînette.
// Abscisse : d = −VERTEX.z (distance horizontale au nez aval), brin selon
// le signe de VERTEX.x. Inactif (le funiculaire) tant que n_appuis < 2.
uniform int n_appuis = 0;
uniform vec4 appuis[12];          // d des appuis, 4 par vec4, croissants
uniform float signe_montee = 1.0; // signe de x du brin montée
uniform int n_charges_m = 0;
uniform vec4 charges_m[32];       // (d, P/H) × 2 par vec4, brin montée
uniform int n_charges_d = 0;
uniform vec4 charges_d[32];       // brin descente
uniform float w_m = 0.0;          // charge répartie / H (1/m), brin montée
uniform float w_d = 0.0;

float appui(int i) {
	vec4 v = appuis[i / 4];
	int k = i - (i / 4) * 4;
	return k == 0 ? v.x : (k == 1 ? v.y : (k == 2 ? v.z : v.w));
}

float fleche_points(float d, bool montee) {
	if (n_appuis < 2) {
		return 0.0;
	}
	float x1 = appui(0);
	float x2 = appui(n_appuis - 1);
	if (d <= x1 || d >= x2) {
		return 0.0;
	}
	for (int i = 0; i < n_appuis - 1; i++) {
		float a0 = appui(i);
		float a1 = appui(i + 1);
		if (d >= a0 && d <= a1) {
			x1 = a0;
			x2 = a1;
			break;
		}
	}
	float l = max(x2 - x1, 0.01);
	float f = -(montee ? w_m : w_d) * (d - x1) * (x2 - d) * 0.5;
	int n = montee ? n_charges_m : n_charges_d;
	for (int j = 0; j < n; j++) {
		vec4 c = montee ? charges_m[j / 2] : charges_d[j / 2];
		vec2 q = (j - (j / 2) * 2) == 0 ? c.xy : c.zw;
		float a = q.x;
		if (a <= x1 || a >= x2) {
			continue;
		}
		f += q.y * (d < a ? (d - x1) * (x2 - a) : (a - x1) * (x2 - d)) / l;
	}
	return f;
}

float phase_brin(float s) {
	if (!effile) {
		return cable_phase;
	}
	float w = clamp((s_poulie - s) / max(s_poulie - s_attache, 1.0), 0.0, 1.0);
	return mix(phase_poulie, cable_phase, w);
}

void vertex() {
	if (slack > 0.0) {
		vec3 down = normalize((inverse(MODEL_MATRIX) * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
		vec3 droite = COLOR.rgb * 2.0 - 1.0;
		float s = UV.y * uv_y_to_meters;
		// les ondulations appartiennent au câble : prises en abscisse
		// MATIÈRE (s − phase), elles avancent avec le tronçon que sa rame
		// entraîne et restent en place sur un tronçon immobile
		float ph_v = (gap_hi > gap_lo && s >= gap_hi) ? phase_upper : phase_brin(s);
		float s_mat = s - ph_v;
		float onde = sin(6.2831853 * s_mat / slack_wave_len) * 0.7
			+ sin(6.2831853 * s_mat / (slack_wave_len * 2.7) + 1.3) * 0.3;
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
	if (n_appuis >= 2) {
		bool montee = sign(VERTEX.x) == signe_montee;
		VERTEX.y -= fleche_points(-VERTEX.z, montee);
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
	float ph = (broken && s_geom >= gap_hi) ? phase_upper : phase_brin(s_geom);
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
