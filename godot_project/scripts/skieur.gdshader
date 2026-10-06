// Skieurs réalistes (06/10/2026) : couleurs choisies par passager.
// UV2.x = numéro de pièce (SkieurMesh.P_*). INSTANCE_CUSTOM.rgb = graines
// aléatoires du passager (ou de son matériel) : chacun s'habille dans des
// palettes de vêtements de ski actuels, veste bicolore ou non, pantalon
// plutôt sombre, casque, écran de masque miroir, peau, cheveux, gants…
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 v_alb;
varying float v_rough;
varying float v_metal;
varying float v_emis;

const vec3 VESTES[16] = vec3[16](
	vec3(0.045, 0.045, 0.052), vec3(0.06, 0.09, 0.22), vec3(0.08, 0.20, 0.58), vec3(0.62, 0.06, 0.06),
	vec3(0.88, 0.33, 0.05), vec3(0.90, 0.74, 0.08), vec3(0.04, 0.40, 0.44), vec3(0.10, 0.30, 0.15),
	vec3(0.32, 0.05, 0.10), vec3(0.86, 0.86, 0.84), vec3(0.55, 0.56, 0.58), vec3(0.82, 0.30, 0.50),
	vec3(0.30, 0.16, 0.50), vec3(0.42, 0.40, 0.28), vec3(0.20, 0.55, 0.80), vec3(0.08, 0.08, 0.10));
const vec3 PANTALONS[10] = vec3[10](
	vec3(0.035, 0.035, 0.04), vec3(0.035, 0.035, 0.04), vec3(0.035, 0.035, 0.04), vec3(0.14, 0.14, 0.16),
	vec3(0.07, 0.09, 0.18), vec3(0.82, 0.82, 0.80), vec3(0.55, 0.49, 0.37), vec3(0.24, 0.26, 0.15),
	vec3(0.45, 0.06, 0.06), vec3(0.22, 0.22, 0.24));
const vec3 CASQUES[8] = vec3[8](
	vec3(0.04, 0.04, 0.045), vec3(0.88, 0.88, 0.87), vec3(0.36, 0.37, 0.39), vec3(0.06, 0.10, 0.25),
	vec3(0.60, 0.08, 0.07), vec3(0.55, 0.78, 0.70), vec3(0.10, 0.22, 0.14), vec3(0.04, 0.04, 0.045));
const vec3 ECRANS[6] = vec3[6](
	vec3(1.00, 0.52, 0.08), vec3(0.15, 0.42, 1.00), vec3(0.80, 0.83, 0.88), vec3(0.95, 0.20, 0.30),
	vec3(0.20, 0.80, 0.40), vec3(0.90, 0.70, 0.15));
const vec3 PEAUX[6] = vec3[6](
	vec3(0.95, 0.78, 0.66), vec3(0.90, 0.71, 0.57), vec3(0.82, 0.61, 0.46), vec3(0.70, 0.50, 0.36),
	vec3(0.52, 0.35, 0.24), vec3(0.34, 0.22, 0.15));
const vec3 CHEVEUX[6] = vec3[6](
	vec3(0.72, 0.58, 0.32), vec3(0.42, 0.29, 0.17), vec3(0.20, 0.13, 0.08), vec3(0.05, 0.045, 0.04),
	vec3(0.50, 0.20, 0.08), vec3(0.62, 0.62, 0.62));
const vec3 CHAUSSURES[7] = vec3[7](
	vec3(0.04, 0.04, 0.045), vec3(0.04, 0.04, 0.045), vec3(0.86, 0.86, 0.85), vec3(0.32, 0.33, 0.35),
	vec3(0.08, 0.26, 0.62), vec3(0.62, 0.07, 0.06), vec3(0.85, 0.40, 0.06));
const vec3 GANTS[5] = vec3[5](
	vec3(0.03, 0.03, 0.035), vec3(0.03, 0.03, 0.035), vec3(0.20, 0.20, 0.22), vec3(0.36, 0.22, 0.11),
	vec3(0.60, 0.60, 0.62));
const vec3 BONNETS[8] = vec3[8](
	vec3(0.70, 0.10, 0.10), vec3(0.08, 0.10, 0.25), vec3(0.88, 0.86, 0.80), vec3(0.15, 0.15, 0.17),
	vec3(0.85, 0.55, 0.10), vec3(0.20, 0.45, 0.30), vec3(0.75, 0.40, 0.55), vec3(0.30, 0.55, 0.75));
const vec3 SACS[5] = vec3[5](
	vec3(0.04, 0.04, 0.045), vec3(0.25, 0.26, 0.28), vec3(0.55, 0.08, 0.06), vec3(0.07, 0.10, 0.22),
	vec3(0.85, 0.45, 0.06));
const vec3 SKIS[9] = vec3[9](
	vec3(0.04, 0.04, 0.05), vec3(0.88, 0.88, 0.86), vec3(0.70, 0.07, 0.06), vec3(0.08, 0.30, 0.75),
	vec3(0.12, 0.55, 0.25), vec3(0.92, 0.78, 0.08), vec3(0.92, 0.42, 0.06), vec3(0.40, 0.18, 0.60),
	vec3(0.55, 0.57, 0.60));
const vec3 FIXATIONS[5] = vec3[5](
	vec3(0.04, 0.04, 0.045), vec3(0.85, 0.85, 0.84), vec3(0.65, 0.06, 0.05), vec3(0.90, 0.45, 0.05),
	vec3(0.35, 0.36, 0.38));

float h(float x) {
	return fract(sin(x * 12.9898 + 78.233) * 43758.5453);
}

vec3 au_choix(float r, int n, int palette) {
	int i = clamp(int(r * float(n)), 0, n - 1);
	if (palette == 0) return VESTES[i];
	if (palette == 1) return PANTALONS[i];
	if (palette == 2) return CASQUES[i];
	if (palette == 3) return ECRANS[i];
	if (palette == 4) return PEAUX[i];
	if (palette == 5) return CHEVEUX[i];
	if (palette == 6) return CHAUSSURES[i];
	if (palette == 7) return GANTS[i];
	if (palette == 8) return BONNETS[i];
	if (palette == 9) return SACS[i];
	if (palette == 10) return SKIS[i];
	return FIXATIONS[i];
}

void vertex() {
	int part = int(UV2.x + 0.5);
	float g = INSTANCE_CUSTOM.r * 131.0 + INSTANCE_CUSTOM.g * 17.0 + INSTANCE_CUSTOM.b * 7.0;
	vec3 veste = au_choix(h(g + 1.0), 16, 0);
	vec3 veste2 = h(g + 2.0) < 0.5 ? veste : au_choix(h(g + 3.0), 16, 0);
	vec3 peau = au_choix(h(g + 4.0), 6, 4);
	vec3 c = veste;
	float rough = 0.62;
	float metal = 0.0;
	float emis = 0.0;
	if (part == 0) { c = peau; rough = 0.55; }
	else if (part == 1) { c = veste; rough = 0.58; }
	else if (part == 2) { c = veste2; rough = 0.58; }
	else if (part == 3) { c = au_choix(h(g + 5.0), 10, 1); rough = 0.72; }
	else if (part == 4) { c = au_choix(h(g + 6.0), 7, 6); rough = 0.30; }
	else if (part == 5) { c = vec3(0.62, 0.63, 0.66); metal = 0.85; rough = 0.30; }
	else if (part == 6) { c = vec3(0.025, 0.025, 0.03); rough = 0.75; }
	else if (part == 7) { c = h(g + 7.0) < 0.15 ? veste : au_choix(h(g + 8.0), 5, 7); rough = 0.80; }
	else if (part == 8) { c = au_choix(h(g + 9.0), 8, 2); rough = h(g + 10.0) < 0.5 ? 0.30 : 0.70; }
	else if (part == 9) { c = au_choix(h(g + 11.0), 6, 3); metal = 0.92; rough = 0.08; }
	else if (part == 10) { c = h(g + 12.0) < 0.6 ? vec3(0.03, 0.03, 0.035) : veste2; rough = 0.50; }
	else if (part == 11) { c = au_choix(h(g + 13.0), 5, 9); rough = 0.70; }
	else if (part == 12) { c = au_choix(h(g + 14.0), 8, 8); rough = 0.95; }
	else if (part == 13) { c = au_choix(h(g + 15.0), 6, 5); rough = 0.65; }
	else if (part == 14) {
		// tour de cou : 30 % n'en portent pas (peau)
		c = h(g + 16.0) < 0.30 ? peau : (h(g + 17.0) < 0.5 ? vec3(0.04, 0.04, 0.05) : veste2);
		rough = 0.85;
	}
	else if (part == 15) { c = au_choix(h(g + 18.0), 9, 10); rough = 0.25; }
	else if (part == 16) { c = au_choix(h(g + 19.0), 9, 10); rough = 0.25; }
	else if (part == 17) { c = vec3(0.03, 0.03, 0.035); rough = 0.20; }
	else if (part == 18) { c = au_choix(h(g + 20.0), 5, 11); rough = 0.35; }
	else if (part == 19) {
		float r = h(g + 21.0);
		c = r < 0.4 ? vec3(0.05, 0.05, 0.06) : (r < 0.7 ? vec3(0.70, 0.72, 0.75) : au_choix(h(g + 22.0), 9, 10));
		metal = 0.6; rough = 0.30;
	}
	else if (part == 20) { c = vec3(0.04, 0.04, 0.045); rough = 0.70; }
	else if (part == 21) { c = au_choix(h(g + 23.0), 9, 10); rough = 0.30; }
	else if (part == 22) { c = vec3(0.55, 0.70, 0.95); rough = 0.20; emis = 0.9; }
	else if (part == 23) { c = h(g + 24.0) < 0.5 ? au_choix(h(g + 14.0), 8, 8) : au_choix(h(g + 25.0), 8, 8); rough = 0.95; }
	v_alb = c;
	v_rough = rough;
	v_metal = metal;
	v_emis = emis;
}

void fragment() {
	ALBEDO = v_alb;
	ROUGHNESS = v_rough;
	METALLIC = v_metal;
	EMISSION = v_alb * v_emis;
}
