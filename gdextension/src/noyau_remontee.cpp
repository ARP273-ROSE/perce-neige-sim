#include "noyau_remontee.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {
// chronos de l'étape (µs, cumulés jusqu'à la lecture) : avance, poses, appels GDScript, MultiMesh, total
inline double maintenant_us() {
	return std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

const StringName &nom_phi_init() {
	static StringName n("phi");
	return n;
}

}

#define nom_phi nom_phi_init()
#define nom_psi nom_psi_init()

namespace {

const StringName &nom_psi_init() {
	static StringName n("psi");
	return n;
}

double smoothstep(double a, double b, double x) {
	if (b == a) {
		return x < a ? 0.0 : 1.0;
	}
	double t = std::clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

double signe(double x) {
	return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0);
}

} // namespace

static inline float demi_flottant(uint16_t v) {
	const uint32_t signe = uint32_t(v & 0x8000) << 16;
	const uint32_t exposant = (v >> 10) & 0x1f;
	const uint32_t mantisse = v & 0x3ff;
	uint32_t bits;
	if (exposant == 0) {
		if (mantisse == 0) {
			bits = signe;
		} else {
			// dénormal : normalisé pour le format 32 bits
			uint32_t e = 127 - 14;
			uint32_t m = mantisse;
			while ((m & 0x400) == 0) {
				m <<= 1;
				e--;
			}
			bits = signe | (e << 23) | ((m & 0x3ff) << 13);
		}
	} else if (exposant == 31) {
		bits = signe | 0x7f800000 | (mantisse << 13);
	} else {
		bits = signe | ((exposant + 127 - 15) << 23) | (mantisse << 13);
	}
	float f;
	memcpy(&f, &bits, 4);
	return f;
}

Array NoyauRemontee::fusion_relief(const PackedFloat32Array &h, const PackedFloat32Array &h0, const PackedByteArray &ecart,
		int nx, int nz, int k, const PackedFloat32Array &rects, double x0, double z0, double dx, double dz) const {
	Array sortie;
	const int64_t nj = int64_t(nx - 1) * k + 1;
	const int64_t ni = int64_t(nz - 1) * k + 1;
	if (k < 1 || h.size() != nx * nz || h0.size() != nx * nz || ecart.size() != ni * nj * 2) {
		return sortie;
	}
	const float *ph = h.ptr();
	const float *ph0 = h0.ptr();
	const uint8_t *pe = ecart.ptr();

	// mailles à 25 m retouchées (déblais), élargies d'une maille
	std::vector<uint8_t> tenu(size_t(nx) * nz, 0);
	for (int i = 0; i < nz; i++) {
		for (int j = 0; j < nx; j++) {
			if (std::fabs(ph[i * nx + j] - ph0[i * nx + j]) > 0.02f) {
				for (int a = std::max(i - 1, 0); a <= std::min(i + 1, nz - 1); a++) {
					for (int b = std::max(j - 1, 0); b <= std::min(j + 1, nx - 1); b++) {
						tenu[size_t(a) * nx + b] = 1;
					}
				}
			}
		}
	}
	// nœuds sous un aménagement
	const double px = dx / k;
	const double pz = dz / k;
	std::vector<uint8_t> coupe(size_t(ni * nj), 0);
	for (int64_t q = 0; q + 3 < rects.size(); q += 4) {
		const int64_t ja = std::max<int64_t>(int64_t(std::ceil((rects[q] - x0) / px)), 0);
		const int64_t ia = std::max<int64_t>(int64_t(std::ceil((rects[q + 1] - z0) / pz)), 0);
		const int64_t jb = std::min<int64_t>(int64_t(std::floor((rects[q + 2] - x0) / px)), nj - 1);
		const int64_t ib = std::min<int64_t>(int64_t(std::floor((rects[q + 3] - z0) / pz)), ni - 1);
		for (int64_t i = ia; i <= ib; i++) {
			std::fill(coupe.begin() + i * nj + ja, coupe.begin() + i * nj + std::max(jb + 1, ja), uint8_t(1));
		}
	}

	PackedFloat32Array hn;
	hn.resize(ni * nj);
	float *ps = hn.ptrw();
	PackedByteArray fine;
	fine.resize(int64_t(nx - 1) * (nz - 1));
	uint8_t *pf = fine.ptrw();
	memset(pf, 0, size_t(fine.size()));
	const float inv = 1.0f / k;
	for (int64_t i = 0; i < ni; i++) {
		const int ci = int(std::min<int64_t>(i / k, nz - 2));
		const float v = float(i - int64_t(ci) * k) * inv;
		for (int64_t j = 0; j < nj; j++) {
			const int cj = int(std::min<int64_t>(j / k, nx - 2));
			const float u = float(j - int64_t(cj) * k) * inv;
			const size_t c0 = size_t(ci) * nx + cj;
			const float a = ph[c0];
			const float b = ph[c0 + 1];
			const float cc = ph[c0 + nx];
			const float d = ph[c0 + nx + 1];
			// même découpe que les tuiles
			const float base = u + v <= 1.0f ? a + (b - a) * u + (cc - a) * v : d + (cc - d) * (1.0f - u) + (b - d) * (1.0f - v);
			const int64_t q = i * nj + j;
			uint16_t brut;
			memcpy(&brut, pe + q * 2, 2);
			float e = demi_flottant(brut);
			if (e != 0.0f && (coupe[size_t(q)] || tenu[c0] || tenu[c0 + 1] || tenu[c0 + nx] || tenu[c0 + nx + 1])) {
				const float l0 = (1.0f - tenu[c0]) * (1.0f - u) + (1.0f - tenu[c0 + 1]) * u;
				const float l1 = (1.0f - tenu[c0 + nx]) * (1.0f - u) + (1.0f - tenu[c0 + nx + 1]) * u;
				const float libre = l0 * (1.0f - v) + l1 * v;
				e = coupe[size_t(q)] ? 0.0f : e * libre * libre;
			}
			ps[q] = base + e;
			if (e != 0.0f) {
				// toutes les mailles qui touchent ce nœud
				const int i_a = int(i % k == 0 ? std::max<int64_t>(i / k - 1, 0) : i / k);
				const int j_a = int(j % k == 0 ? std::max<int64_t>(j / k - 1, 0) : j / k);
				for (int a2 = i_a; a2 <= ci; a2++) {
					for (int b2 = j_a; b2 <= cj; b2++) {
						pf[size_t(a2) * (nx - 1) + b2] = 1;
					}
				}
			}
		}
	}
	// nœuds à 25 m : mêmes altitudes, pour les tuiles et le raccord au bord de la grille suiveuse
	PackedFloat32Array recale;
	recale.resize(int64_t(nx) * nz);
	float *pr = recale.ptrw();
	for (int i = 0; i < nz; i++) {
		for (int j = 0; j < nx; j++) {
			pr[size_t(i) * nx + j] = ps[int64_t(i) * k * nj + int64_t(j) * k];
		}
	}
	sortie.append(hn);
	sortie.append(fine);
	sortie.append(recale);
	return sortie;
}

void NoyauRemontee::_bind_methods() {
	ClassDB::bind_method(D_METHOD("fusion_relief", "h", "h0", "ecart", "nx", "nz", "k", "rects", "x0", "z0", "dx", "dz"), &NoyauRemontee::fusion_relief);
	ClassDB::bind_method(D_METHOD("set_boucle", "boucle", "cumul", "longueur"), &NoyauRemontee::set_boucle);
	ClassDB::bind_method(D_METHOD("set_zones", "debut", "fin", "code", "x_haut", "x_bas"), &NoyauRemontee::set_zones);
	ClassDB::bind_method(D_METHOD("set_appuis", "appuis"), &NoyauRemontee::set_appuis);
	ClassDB::bind_method(D_METHOD("set_constantes", "constantes"), &NoyauRemontee::set_constantes);
	ClassDB::bind_method(D_METHOD("set_vehicules", "vehicules", "pinces", "susps", "corps", "s", "phi", "psi"),
			&NoyauRemontee::set_vehicules);
	ClassDB::bind_method(D_METHOD("set_charges", "tires"), &NoyauRemontee::set_charges);
	ClassDB::bind_method(D_METHOD("set_charge_joueur", "i", "psi0"), &NoyauRemontee::set_charge_joueur);
	ClassDB::bind_method(D_METHOD("set_vitesse", "vitesse"), &NoyauRemontee::set_vitesse);
	ClassDB::bind_method(D_METHOD("set_temps", "tab_s"), &NoyauRemontee::set_temps);
	ClassDB::bind_method(D_METHOD("set_ligne", "ligne"), &NoyauRemontee::set_ligne);
	ClassDB::bind_method(D_METHOD("etape", "dt", "regime", "vue", "vue_active", "corps_actifs", "onde_amp", "onde_t",
								 "a_montee", "charges_actives"),
			&NoyauRemontee::etape);
	ClassDB::bind_method(D_METHOD("get_paquets"), &NoyauRemontee::get_paquets);
	ClassDB::bind_method(D_METHOD("fleche_en", "d", "montee"), &NoyauRemontee::fleche_en);
	ClassDB::bind_method(D_METHOD("points", "s"), &NoyauRemontee::points);
	ClassDB::bind_method(D_METHOD("touches", "pylones_d", "voie"), &NoyauRemontee::touches);
	ClassDB::bind_method(D_METHOD("en_gare"), &NoyauRemontee::en_gare);
	ClassDB::bind_method(D_METHOD("set_portillons", "xa"), &NoyauRemontee::set_portillons);
	ClassDB::bind_method(D_METHOD("passages"), &NoyauRemontee::passages);
	ClassDB::bind_method(D_METHOD("set_lointains", "multimeshes", "relatives", "seuil", "jusqua"), &NoyauRemontee::set_lointains);
	ClassDB::bind_method(D_METHOD("set_calage", "i", "d", "y_t", "pente_m", "pente_d", "dist", "d0", "pas", "y_m", "y_d", "paires_m", "paires_d"), &NoyauRemontee::set_calage);
	ClassDB::bind_method(D_METHOD("a_calage", "i"), &NoyauRemontee::a_calage);
	ClassDB::bind_method(D_METHOD("caler", "i"), &NoyauRemontee::caler);
	ClassDB::bind_method(D_METHOD("chronos"), &NoyauRemontee::chronos);
}

// --- configuration -----------------------------------------------------------

void NoyauRemontee::set_boucle(const PackedVector3Array &p_boucle, const PackedFloat32Array &p_cumul, double p_longueur) {
	boucle = p_boucle;
	cumul = p_cumul;
	longueur = p_longueur;
}

void NoyauRemontee::set_zones(const PackedFloat32Array &debut, const PackedFloat32Array &fin, const PackedInt32Array &code,
		const PackedFloat32Array &x_haut, const PackedFloat32Array &x_bas) {
	z_debut.assign(debut.ptr(), debut.ptr() + debut.size());
	z_fin.assign(fin.ptr(), fin.ptr() + fin.size());
	z_code.assign(code.ptr(), code.ptr() + code.size());
	z_haut.assign(x_haut.ptr(), x_haut.ptr() + x_haut.size());
	z_bas.assign(x_bas.ptr(), x_bas.ptr() + x_bas.size());
}

void NoyauRemontee::set_appuis(const PackedFloat32Array &p_appuis) {
	appuis.assign(p_appuis.ptr(), p_appuis.ptr() + p_appuis.size());
	for (int b = 0; b < 2; b++) {
		charges_portee[b].assign(appuis.size(), {});
	}
}

void NoyauRemontee::set_constantes(const Dictionary &c) {
	vitesse = c.get("vitesse", vitesse);
	v_emb = c.get("v_embarquement", v_emb);
	l_frein = c.get("l_frein", l_frein);
	l_ouverture = c.get("l_ouverture", l_ouverture);
	fixe = c.get("fixe", fixe);
	sens_droite = c.get("sens_droite", sens_droite);
	signe_montee = c.get("signe_montee", signe_montee);
	cabine = c.get("cabine", cabine);
	masse = c.get("masse", masse);
	charge_montee = c.get("charge_montee", charge_montee);
	longueur_pendule = c.get("longueur_pendule", longueur_pendule);
	pivot = c.get("pivot", pivot);
	guide_l = c.get("guide_l", guide_l);
	guide_gorge = c.get("guide_gorge", guide_gorge);
	guide_ouvert = c.get("guide_ouvert", guide_ouvert);
	guide_bras = c.get("guide_bras", guide_bras);
	poids[0] = c.get("poids_montee", poids[0]);
	poids[1] = c.get("poids_descente", poids[1]);
	w_veh[0] = c.get("w_montee", w_veh[0]);
	w_veh[1] = c.get("w_descente", w_veh[1]);
}

void NoyauRemontee::set_vehicules(const Array &p_vehicules, const Array &p_pinces, const Array &p_susps, const Array &p_corps,
		const PackedFloat64Array &s, const PackedFloat32Array &p_phi, const PackedFloat32Array &p_psi) {
	const int64_t n = p_vehicules.size();
	auto noeud = [](const Array &a, int64_t i) -> Node3D * {
		if (i >= a.size()) {
			return nullptr;
		}
		return Object::cast_to<Node3D>(a[i]);
	};
	vehicules.resize(n);
	pinces.resize(n);
	susps.resize(n);
	corps.resize(n);
	s_veh.resize(n);
	phi.assign(n, 0.0);
	psi.assign(n, 0.0);
	dphi.assign(n, 0.0);
	dpsi.assign(n, 0.0);
	p_prec.assign(n, Vector3());
	v_prec.assign(n, Vector3());
	a_f.assign(n, Vector3());
	n_mes.assign(n, 0);
	e_ouv.assign(n, -1.0f);
	e_gc.assign(n, -1.0f);
	e_porte.assign(n, -1.0f);
	pose_veh.assign(n, Transform3D());
	loin_veh.assign(n, 0);
	for (int64_t i = 0; i < n; i++) {
		vehicules[i] = noeud(p_vehicules, i);
		pinces[i] = noeud(p_pinces, i);
		susps[i] = noeud(p_susps, i);
		corps[i] = noeud(p_corps, i);
		s_veh[i] = i < s.size() ? s[i] : 0.0;
		if (i < p_phi.size()) {
			phi[i] = p_phi[i];
		}
		if (i < p_psi.size()) {
			psi[i] = p_psi[i];
		}
	}
}

// --- géométrie ---------------------------------------------------------------

void NoyauRemontee::set_charges(const PackedFloat32Array &p_tires) {
	psi0_tire.assign(vehicules.size(), 0.0);
	for (size_t i = 0; i < psi0_tire.size() && (int64_t)i < p_tires.size(); i++) {
		psi0_tire[i] = p_tires[i];
	}
}

// comme LigneRemontee.limite_guide
double NoyauRemontee::limite_guide(double s) const {
	double lim = 1e9;
	if (guide_l <= 0.0) {
		return lim;
	}
	auto positif = [this](double x) {
		x = std::fmod(x, longueur);
		return x < 0.0 ? x + longueur : x;
	};
	for (size_t k = 0; k < z_debut.size(); k++) {
		const double d = std::min(positif(z_debut[k] - s), positif(s - z_fin[k]));
		if (d < guide_l) {
			const double t = std::clamp((d - 0.5) / (guide_l - 0.5), 0.0, 1.0);
			const double lisse = t * t * (3.0 - 2.0 * t);
			lim = std::min(lim, (guide_gorge + (guide_ouvert - guide_gorge) * lisse) / guide_bras);
		}
	}
	return lim;
}

NoyauRemontee::Zone NoyauRemontee::zone(double s) const {
	s = std::fmod(s, longueur);
	if (s < 0.0) {
		s += longueur;
	}
	for (size_t k = 0; k < z_debut.size(); k++) {
		if (s >= z_debut[k] && s <= z_fin[k]) {
			return { (int)k, s - z_debut[k], z_fin[k] - z_debut[k] };
		}
	}
	return { -1, 0.0, 0.0 };
}

double NoyauRemontee::vitesse_en(double s) const {
	Zone z = zone(s);
	if (z.idx < 0 || fixe) {
		return vitesse;
	}
	const double t = std::clamp(std::min(z.x, z.l - z.x) / l_frein, 0.0, 1.0);
	const double lisse = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
	return std::sqrt(std::max(0.0, vitesse * vitesse - (vitesse * vitesse - v_emb * v_emb) * lisse));
}

void NoyauRemontee::point_cable(double s, Vector3 &p, Vector3 &d) const {
	const int64_t n = boucle.size();
	if (n < 2 || longueur <= 0.0) {
		p = Vector3();
		d = Vector3(0, 0, -1);
		return;
	}
	s = std::fmod(s, longueur);
	if (s < 0.0) {
		s += longueur;
	}
	const Vector3 *b = boucle.ptr();
	const float *c = cumul.ptr();
	if (s >= c[n - 1]) {
		const Vector3 &a = b[n - 1];
		const Vector3 &e = b[0];
		const double u = (s - c[n - 1]) / std::max(longueur - (double)c[n - 1], 0.001);
		p = a.lerp(e, (real_t)u);
		d = e - a;
		return;
	}
	int64_t lo = 0, hi = n - 1;
	while (hi - lo > 1) {
		const int64_t mid = (lo + hi) / 2;
		if (c[mid] <= s) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	const double u = (s - c[lo]) / std::max((double)c[hi] - c[lo], 0.001);
	p = b[lo].lerp(b[hi], (real_t)u);
	d = b[hi] - b[lo];
}

int NoyauRemontee::portee_de(double d) const {
	for (size_t i = 0; i + 1 < appuis.size(); i++) {
		if (d >= appuis[i] && d <= appuis[i + 1]) {
			return (int)i;
		}
	}
	return -1;
}

double NoyauRemontee::fleche(double d, bool montee, double onde_amp, double onde_t, double a_montee) const {
	const size_t n = appuis.size();
	if (n < 2 || d <= appuis[0] || d >= appuis[n - 1]) {
		return 0.0;
	}
	const int ip = portee_de(d);
	if (ip < 0) {
		return 0.0;
	}
	const int b = montee ? 0 : 1;
	const double x1 = appuis[ip];
	const double x2 = appuis[ip + 1];
	const double l = std::max(x2 - x1, 0.01);
	double f = -w_veh[b] * (d - x1) * (x2 - d) * 0.5;
	for (const Vector2 &c : charges_portee[b][ip]) {
		const double a = c.x;
		if (a <= x1 || a >= x2) {
			continue;
		}
		f += c.y * (d < a ? (d - x1) * (x2 - a) : (a - x1) * (x2 - d)) / l;
	}
	if (onde_amp > 0.0) {
		const double w = Math_PI * std::sqrt(9.81 * a_montee) / l;
		const double ph = montee ? 0.0 : 1.5708;
		f += onde_amp * (montee ? 1.0 : 0.5) * std::sin(w * onde_t + ph) * std::sin(Math_PI * (d - x1) / l);
	}
	return f;
}

PackedVector3Array NoyauRemontee::points(const PackedFloat32Array &s_in) const {
	PackedVector3Array out;
	out.resize(s_in.size() * 2);
	Vector3 *o = out.ptrw();
	for (int64_t k = 0; k < s_in.size(); k++) {
		point_cable(s_in[k], o[2 * k], o[2 * k + 1]);
	}
	return out;
}

// --- une image -----------------------------------------------------------------

static const double PAS_TAB_S = 0.05;

void NoyauRemontee::set_temps(const PackedFloat32Array &p_tab_s) {
	tab_s.assign(p_tab_s.ptr(), p_tab_s.ptr() + p_tab_s.size());
	s_repere.assign(s_veh.size(), -1.0);
	t_veh.assign(s_veh.size(), 0.0);
}

double NoyauRemontee::t_de_s(double s) const {
	s = std::fmod(s, longueur);
	if (s < 0.0) {
		s += longueur;
	}
	size_t lo = 0;
	size_t hi = tab_s.size() - 1;
	while (hi - lo > 1) {
		const size_t m = (lo + hi) / 2;
		if ((double)tab_s[m] <= s) {
			lo = m;
		} else {
			hi = m;
		}
	}
	const double u = (s - (double)tab_s[lo]) / std::max((double)tab_s[hi] - (double)tab_s[lo], 1e-4);
	return ((double)lo + u) * PAS_TAB_S;
}

double NoyauRemontee::s_de_t(double t) const {
	const size_t der = tab_s.size() - 1;
	size_t k = (size_t)(t / PAS_TAB_S);
	if (k > der) {
		k = der;
	}
	const double u = (t - (double)k * PAS_TAB_S) / PAS_TAB_S;
	const size_t k1 = std::min(k + 1, der);
	return (double)tab_s[k] + ((double)tab_s[k1] - (double)tab_s[k]) * u;
}

PackedFloat64Array NoyauRemontee::etape(double dt, double regime, const Vector3 &vue, bool vue_active, bool corps_actifs,
		double onde_amp, double onde_t, double a_montee, bool charges_actives) {
	const size_t n = s_veh.size();
	d_onde_amp = onde_amp;
	d_onde_t = onde_t;
	d_a_montee = a_montee;
	const double t_debut = maintenant_us();
	// 1. avance sur la boucle (profil de vitesse des lanceurs) ; passages
	// devant les portillons (fin du demi-tour)
	passages_derniers.clear();
	const bool par_temps = tab_s.size() > 1;
	const double t_boucle = PAS_TAB_S * (double)(tab_s.size() - 1);
	if (par_temps && t_veh.size() != n) {
		t_veh.assign(n, 0.0);
		s_repere.assign(n, -1.0);
	}
	for (size_t i = 0; i < n; i++) {
		const Zone z0 = zone(s_veh[i]);
		double s;
		if (par_temps) {
			// temps de parcours, pas distance cumulée : à grands pas (images longues, lignes lointaines),
			// s += v·dt passait les zones lentes de travers et les véhicules finissaient collés
			if (s_repere[i] != s_veh[i]) {
				t_veh[i] = t_de_s(s_veh[i]);
			}
			double t = std::fmod(t_veh[i] + regime * dt, t_boucle);
			if (t < 0.0) {
				t += t_boucle;
			}
			t_veh[i] = t;
			s = s_de_t(t);
			s_repere[i] = s;
		} else {
			s = s_veh[i] + vitesse_en(s_veh[i]) * regime * dt;
			s = std::fmod(s, longueur);
			if (s < 0.0) {
				s += longueur;
			}
		}
		s_veh[i] = s;
		if (z0.idx >= 0 && (size_t)z0.idx < z_xa.size()) {
			const Zone z1 = zone(s);
			const double xa = z_xa[z0.idx];
			if (z1.idx == z0.idx && z0.x < xa && z1.x >= xa) {
				passages_derniers.push_back(z0.idx);
				passages_derniers.push_back((int)i);
			}
		}
	}
	// 2. charges ponctuelles (véhicules en ligne), par brin puis par portée
	if (charges_actives && appuis.size() >= 2) {
		for (int b = 0; b < 2; b++) {
			charges[b].clear();
			for (auto &l : charges_portee[b]) {
				l.clear();
			}
		}
		for (size_t i = 0; i < n; i++) {
			if (zone(s_veh[i]).idx >= 0) {
				continue;
			}
			Vector3 p, d;
			point_cable(s_veh[i], p, d);
			const int b = signe(p.x) == signe_montee ? 0 : 1;
			if (charges[b].size() < 64) {
				charges[b].push_back(Vector2(-p.z, poids[b]));
			}
		}
		for (int b = 0; b < 2; b++) {
			for (const Vector2 &c : charges[b]) {
				const int ip = portee_de(c.x);
				if (ip >= 0) {
					charges_portee[b][ip].push_back(c);
				}
			}
		}
		paquets.resize(2 * 32 * 4 + 2);
		float *q = paquets.ptrw();
		for (int b = 0; b < 2; b++) {
			for (int j = 0; j < 32; j++) {
				const size_t i0 = j * 2, i1 = j * 2 + 1;
				const Vector2 a = i0 < charges[b].size() ? charges[b][i0] : Vector2();
				const Vector2 c = i1 < charges[b].size() ? charges[b][i1] : Vector2();
				float *e = q + (b * 32 + j) * 4;
				e[0] = a.x;
				e[1] = a.y;
				e[2] = c.x;
				e[3] = c.y;
			}
			q[2 * 32 * 4 + b] = (float)charges[b].size();
		}
	}
	const double t_avance = maintenant_us();
	chronos_us[0] += t_avance - t_debut;
	double t_set = 0.0, t_call = 0.0;
	// 3. poses (niveau de détail selon la distance au point de vue)
	tour = (tour + 1) % 4;
	gare_derniere.clear();
	const double sx = sens_droite ? 1.0 : -1.0;
	const Vector3 pv(pivot.x * sx, pivot.y, pivot.z);
	for (size_t i = 0; i < n; i++) {
		Node3D *v = vehicules[i];
		if (v == nullptr) {
			continue;
		}
		const double s = s_veh[i];
		Vector3 p, d3;
		point_cable(s, p, d3);
		bool proche = true;
		bool au_dela = false;          // au-delà de 700 m : MultiMesh seul
		double dt_i = dt;
		// lointain (MultiMesh) : nœud caché, pose seule — le balancement et les pièces animées ne se
		// voient pas à cette distance. Décidé avant de sauter les véhicules au-delà de 700 m : sinon un
		// nœud resté visible (set_lointains les remontre tous quand la portée change) le restait, figé et
		// en détail complet, hors du MultiMesh (relevé du 06/11/2026 : 115 sièges des Lanches dessinés en
		// entier à plus de 700 m)
		bool loin = false;
		if (!mm_rid.empty() && vue_active) {
			const double dx = p.x - vue.x, dz = p.z - vue.z;
			loin = dx * dx + dz * dz > mm_seuil * mm_seuil;
		}
		if ((char)loin != loin_veh[i]) {
			loin_veh[i] = (char)loin;
			v->set_visible(!loin);
		}
		if (vue_active) {
			const double dx = p.x - vue.x, dz = p.z - vue.z;
			const double d2 = dx * dx + dz * dz;
			proche = d2 < 60.0 * 60.0;
			// au-delà de 700 m, seul le MultiMesh le dessine, jusqu'à sa portée : sa pose suit, une image sur quatre
			if (d2 > 700.0 * 700.0) {
				if (!(loin && d2 < mm_jusqua * mm_jusqua)) {
					continue;
				}
				au_dela = true;
			}
			if (d2 > 250.0 * 250.0) {
				if ((i + tour) % 4 != 0) {
					continue;
				}
				dt_i = 0.0;
			}
		}
		const Zone z = zone(s);
		if (z.idx >= 0 && !au_dela) {
			gare_derniere.push_back((int)i);
		}
		const bool montee_v = signe(p.x) == signe_montee;
		if (appuis.size() >= 2 && z.idx < 0) {
			p.y -= (real_t)fleche(-p.z, montee_v, onde_amp, onde_t, a_montee);
		}
		// cap : en ligne la tangente, en gare la corde de 3 m
		Vector3 dirh;
		if (z.idx < 0) {
			dirh = d3;
		} else {
			Vector3 pa, pb, dd;
			point_cable(s + 1.5, pa, dd);
			point_cable(s - 1.5, pb, dd);
			dirh = pa - pb;
		}
		dirh.y = 0.0;
		if (dirh.length() < 0.001) {
			dirh = Vector3(0, 0, -1);
		}
		const Basis b = Basis::looking_at(dirh.normalized(), Vector3(0, 1, 0));
		Basis bv = b;
		if (!sens_droite) {
			bv = b * Basis::from_scale(Vector3(-1, 1, 1));
		}
		pose_veh[i] = Transform3D(bv, p);
		if (loin) {
			continue;
		}
		double t0s = maintenant_us();
		v->set_transform(pose_veh[i]);
		t_set += maintenant_us() - t0s;
		if (pinces[i] != nullptr) {
			Vector3 r = pinces[i]->get_rotation();
			r.x = (real_t)std::atan2((double)d3.y, (double)Vector2(d3.x, d3.z).length());
			pinces[i]->set_rotation(r);
		}
		// balancement (pendule amorti), comme VehiculeRemontee.balancer
		if (dt_i > 0.0 && susps[i] != nullptr) {
			const bool en_gare = z.idx >= 0;
			const double m = masse + ((montee_v && !cabine) ? charge_montee : 0.0);
			if (n_mes[i] == 0) {
				p_prec[i] = p;
				n_mes[i] = 1;
			} else {
				const Vector3 vel = (p - p_prec[i]) / (real_t)dt_i;
				p_prec[i] = p;
				if (n_mes[i] == 1) {
					v_prec[i] = vel;
					n_mes[i] = 2;
				} else {
					const Vector3 a = ((vel - v_prec[i]) / (real_t)dt_i).limit_length(25.0);
					v_prec[i] = vel;
					a_f[i] = a_f[i].lerp(a, (real_t)std::min(1.0, dt_i * (en_gare ? 3.0 : 15.0)));
					const Vector3 la = bv.inverse().xform(a_f[i]);
					const double g2 = 9.81 + a_f[i].y;
					const double L = longueur_pendule;
					const double w0 = std::sqrt(9.81 / L);
					const double zeta = en_gare ? 0.7 : std::clamp(90.0 / m, 0.03, 0.30);
					const int ns = std::max(1, (int)std::ceil(dt_i / 0.008));
					const double h = dt_i / ns;
					double cible = 0.0;
					if (!en_gare || guide_l <= 0.0) {
						if ((int)i == i_joueur) {
							cible = psi0_joueur;
						} else if (montee_v && i < psi0_tire.size()) {
							cible = psi0_tire[i];
						}
					}
					for (int k = 0; k < ns; k++) {
						const double ddphi = -(g2 / L) * std::sin(phi[i]) - (-la.z / L) * std::cos(phi[i]) - 2.0 * zeta * w0 * dphi[i];
						const double ddpsi = -(g2 / L) * std::sin(psi[i] - cible) - (la.x / L) * std::cos(psi[i]) - 2.0 * zeta * w0 * dpsi[i];
						dphi[i] += ddphi * h;
						dpsi[i] += ddpsi * h;
						phi[i] += dphi[i] * h;
						psi[i] += dpsi[i] * h;
					}
					phi[i] = std::clamp(phi[i], -0.6, 0.6);
					psi[i] = std::clamp(psi[i], -0.6, 0.6);
					// le roulement touche le guide : il garde sa place, et sa vitesse tombe
					const double lim = limite_guide(s);
					if (std::abs(psi[i]) > lim) {
						psi[i] = std::clamp(psi[i], -lim, lim);
						dpsi[i] = 0.0;
					}
					susps[i]->set_rotation(Vector3((real_t)phi[i], 0, (real_t)psi[i]));
					// recopiés dans le véhicule : lus par le GDScript (collisions des
					// tronçons jumelés, bancs de l'arrêt d'urgence)
					v->set(nom_phi, phi[i]);
					v->set(nom_psi, psi[i]);
				}
			}
		}
		// corps de collision (lignes proches), suit le balancement
		if (corps_actifs && proche && corps[i] != nullptr) {
			const Transform3D bal = Transform3D(Basis::from_euler(Vector3((real_t)phi[i], 0, (real_t)(psi[i] * sx))), pv) *
					Transform3D(Basis(), -pv);
			t0s = maintenant_us();
			corps[i]->set_transform(Transform3D(b, p) * bal);
			t_set += maintenant_us() - t0s;
		}
		// pièces animées en gare : appel seulement quand la valeur change
		float ouv = 0.0f, gc = 1.0f, porte = 0.0f;
		if (z.idx >= 0) {
			{
				const double u_ouv = std::min(z.x, z.l - z.x);
				ouv = fixe ? 0.0f : (float)(smoothstep(0.0, l_ouverture, u_ouv) * (1.0 - smoothstep(l_ouverture, l_ouverture + 1.0, u_ouv)));
			}
			const double xh = z_haut[z.idx], xb = z_bas[z.idx];
			gc = (float)(1.0 - std::clamp((z.x - xh) / 2.0, 0.0, 1.0) * std::clamp((xb - z.x) / 2.0, 0.0, 1.0));
			if (cabine) {
				porte = (float)std::clamp((std::min(z.x, z.l - z.x) - l_frein) / 2.0, 0.0, 1.0);
			}
		}
		const double t0c = maintenant_us();
		if (ouv != e_ouv[i]) {
			e_ouv[i] = ouv;
			v->call("ouvrir_pince", ouv);
		}
		if (gc != e_gc[i]) {
			e_gc[i] = gc;
			v->call("garde_corps", gc);
			v->call("bulle", gc);
		}
		if (cabine && porte != e_porte[i]) {
			const bool avant = e_porte[i] > 0.5f;
			e_porte[i] = porte;
			v->call("portes", porte);
			if ((porte > 0.5f) != avant && ligne != nullptr) {
				// portes ouvertes : collisions des vantaux coupées (GDScript)
				ligne->call("_portes_corps", (int64_t)i, porte > 0.5f);
			}
		}
		t_call += maintenant_us() - t0c;
	}
	const double t_poses = maintenant_us();
	chronos_us[1] += t_poses - t_avance - t_call;
	chronos_us[2] += t_call;
	chronos_us[5] += t_set;
	// 4. MultiMesh des lointains : seuls les véhicules à dessiner (ni les proches, ni au-delà de `jusqua`)
	if (!mm_rid.empty()) {
		RenderingServer *rs = RenderingServer::get_singleton();
		for (size_t m = 0; m < mm_rid.size(); m++) {
			PackedFloat32Array buf;
			buf.resize(n * 12);
			float *b = buf.ptrw();
			int nb_vus = 0;
			for (size_t i = 0; i < n; i++) {
				Transform3D t;
				bool montrer = loin_veh[i] != 0;
				if (montrer && vue_active) {
					const Vector3 &o = pose_veh[i].origin;
					const double dx = o.x - vue.x, dz = o.z - vue.z;
					montrer = dx * dx + dz * dz < mm_jusqua * mm_jusqua;
				}
				// instances dessinées tassées en tête : une instance à l'échelle nulle compte quand même
				// tous ses triangles (8,7 M de primitives pour rien, relevés du 04/11/2026)
				if (!montrer) {
					continue;
				}
				t = pose_veh[i] * mm_rel[m];
				float *e = b + nb_vus * 12;
				nb_vus++;
				e[0] = t.basis.rows[0].x; e[1] = t.basis.rows[0].y; e[2] = t.basis.rows[0].z; e[3] = t.origin.x;
				e[4] = t.basis.rows[1].x; e[5] = t.basis.rows[1].y; e[6] = t.basis.rows[1].z; e[7] = t.origin.y;
				e[8] = t.basis.rows[2].x; e[9] = t.basis.rows[2].y; e[10] = t.basis.rows[2].z; e[11] = t.origin.z;
			}
			rs->multimesh_set_buffer(mm_rid[m], buf);
			rs->multimesh_set_visible_instances(mm_rid[m], nb_vus);
		}
	}
	const double t_mm = maintenant_us();
	chronos_us[3] += t_mm - t_poses;
	chronos_us[4] += t_mm - t_debut;
	PackedFloat64Array out;
	out.resize(n);
	double *o = out.ptrw();
	for (size_t i = 0; i < n; i++) {
		o[i] = s_veh[i];
	}
	return out;
}

PackedFloat32Array NoyauRemontee::touches(const PackedFloat32Array &pylones_d, double voie) const {
	PackedFloat32Array out;
	const int64_t np = pylones_d.size();
	if (np == 0) {
		return out;
	}
	// pylônes triés par abscisse (posés dans l'ordre) : recherche par dichotomie
	const float *pd = pylones_d.ptr();
	for (size_t i = 0; i < s_veh.size(); i++) {
		Vector3 p, d3;
		point_cable(s_veh[i], p, d3);
		if (std::fabs(std::fabs(p.x) - voie * 0.5) > 0.3) {
			continue;                    // sur la poulie : loin des batteries
		}
		const double d = -p.z;
		const double montee = signe(p.x) == signe_montee ? 1.0 : 0.0;
		const float *lo = std::lower_bound(pd, pd + np, (float)(d - 6.0));
		for (const float *q = lo; q < pd + np && *q < d + 6.0; q++) {
			const double u = *q - d;
			if (std::fabs(u) < 6.0) {
				out.push_back((float)(q - pd));
				out.push_back((float)montee);
				out.push_back((float)u);
			}
		}
	}
	return out;
}

PackedInt32Array NoyauRemontee::en_gare() const {
	PackedInt32Array out;
	out.resize(gare_derniere.size());
	for (size_t k = 0; k < gare_derniere.size(); k++) {
		out[k] = gare_derniere[k];
	}
	return out;
}

void NoyauRemontee::set_portillons(const PackedFloat32Array &xa) {
	z_xa.assign(xa.ptr(), xa.ptr() + xa.size());
}

PackedInt32Array NoyauRemontee::passages() const {
	PackedInt32Array out;
	out.resize(passages_derniers.size());
	for (size_t k = 0; k < passages_derniers.size(); k++) {
		out[k] = passages_derniers[k];
	}
	return out;
}

void NoyauRemontee::set_lointains(const Array &multimeshes, const Array &relatives, double seuil, double jusqua) {
	mm_rid.clear();
	mm_rel.clear();
	for (int64_t k = 0; k < multimeshes.size() && k < relatives.size(); k++) {
		mm_rid.push_back(multimeshes[k]);
		mm_rel.push_back(relatives[k]);
	}
	mm_seuil = seuil;
	mm_jusqua = jusqua;
	for (size_t i = 0; i < loin_veh.size(); i++) {
		if (loin_veh[i] && vehicules[i] != nullptr) {
			vehicules[i]->set_visible(true);
		}
		loin_veh[i] = 0;
	}
}


void NoyauRemontee::set_calage(int64_t i, double d, double y_t, double pente_m, double pente_d, double dist, double d0,
		double pas, const PackedFloat32Array &y_m, const PackedFloat32Array &y_d, const PackedVector3Array &paires_m,
		const PackedVector3Array &paires_d) {
	if (i < 0) {
		return;
	}
	if ((int64_t)calages.size() <= i) {
		calages.resize(i + 1);
	}
	Calage &c = calages[i];
	c.d = d;
	c.y_t = y_t;
	c.pente[0] = pente_m;
	c.pente[1] = pente_d;
	c.dist = dist;
	c.d0 = d0;
	c.pas = std::max(pas, 1e-4);
	c.y[0].assign(y_m.ptr(), y_m.ptr() + y_m.size());
	c.y[1].assign(y_d.ptr(), y_d.ptr() + y_d.size());
	c.paires[0].assign(paires_m.ptr(), paires_m.ptr() + paires_m.size());
	c.paires[1].assign(paires_d.ptr(), paires_d.ptr() + paires_d.size());
	c.pret = !c.y[0].empty() && !c.y[1].empty();
}

// Hauteur du câble affiché au-dessus de l'axe de la tête, à un recul z (+ vers l'aval) : table sans flèche,
// moins la flèche du moment (comme le Callable de LigneRemontee._caler_galets)
double NoyauRemontee::cable_calage(const Calage &c, int b, double z) const {
	const double dp = c.d - z;
	const std::vector<float> &t = c.y[b];
	const double u = (dp - c.d0) / c.pas;
	const int n = (int)t.size();
	int k = (int)std::floor(u);
	k = std::clamp(k, 0, n - 2);
	const double f = std::clamp(u - k, 0.0, 1.0);
	const double y = t[k] + (t[k + 1] - t[k]) * f;
	return y - fleche(dp, b == 0, d_onde_amp, d_onde_t, d_a_montee) - c.y_t;
}

PackedFloat32Array NoyauRemontee::caler(int64_t i) const {
	PackedFloat32Array out;
	if (!a_calage(i)) {
		return out;
	}
	const Calage &c = calages[i];
	out.resize(3 * (c.paires[0].size() + c.paires[1].size()));
	float *o = out.ptrw();
	for (int b = 0; b < 2; b++) {
		const double cp = std::cos(c.pente[b]);
		const double sp = std::sin(c.pente[b]);
		for (const Vector3 &pr : c.paires[b]) {
			const double zp = pr.x, sgn = pr.y, demi = pr.z;
			double zw = zp * cp;
			double yw = cable_calage(c, b, zw);
			for (int it = 0; it < 3; it++) {
				zw = (zp + yw * sp) / std::max(cp, 0.2);
				yw = cable_calage(c, b, zw);
			}
			double e = std::max(demi, 0.05);
			double y1 = cable_calage(c, b, zw + e);
			double y2 = cable_calage(c, b, zw - e);
			for (int j = 0; j < 2; j++) {
				const double e2 = std::max(demi, 0.05) * std::cos(std::atan2(y2 - y1, 2.0 * e));
				y1 = cable_calage(c, b, zw + e2);
				y2 = cable_calage(c, b, zw - e2);
				e = e2;
			}
			if (demi > 0.05) {
				yw = (y1 + y2) * 0.5;
			}
			const double y_loc = yw * cp + zw * sp;
			const double pente_loc = std::atan2(y2 - y1, 2.0 * e) - c.pente[b];
			o[0] = (float)(y_loc + sgn * c.dist * std::cos(pente_loc));
			o[1] = (float)(zp + sgn * c.dist * std::sin(pente_loc));
			o[2] = (float)pente_loc;
			o += 3;
		}
	}
	return out;
}

// [avance, poses (dont set_transform), appels GDScript, MultiMesh, total, set_transform seuls] en µs cumulés ; remis à zéro
PackedFloat64Array NoyauRemontee::chronos() {
	PackedFloat64Array o;
	o.resize(6);
	for (int k = 0; k < 6; k++) {
		o.set(k, chronos_us[k]);
		chronos_us[k] = 0.0;
	}
	return o;
}
