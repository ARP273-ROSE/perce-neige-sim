#include "noyau_remontee.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

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

void NoyauRemontee::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_boucle", "boucle", "cumul", "longueur"), &NoyauRemontee::set_boucle);
	ClassDB::bind_method(D_METHOD("set_zones", "debut", "fin", "code", "x_haut", "x_bas"), &NoyauRemontee::set_zones);
	ClassDB::bind_method(D_METHOD("set_appuis", "appuis"), &NoyauRemontee::set_appuis);
	ClassDB::bind_method(D_METHOD("set_constantes", "constantes"), &NoyauRemontee::set_constantes);
	ClassDB::bind_method(D_METHOD("set_vehicules", "vehicules", "pinces", "susps", "corps", "s", "phi", "psi"),
			&NoyauRemontee::set_vehicules);
	ClassDB::bind_method(D_METHOD("set_vitesse", "vitesse"), &NoyauRemontee::set_vitesse);
	ClassDB::bind_method(D_METHOD("set_ligne", "ligne"), &NoyauRemontee::set_ligne);
	ClassDB::bind_method(D_METHOD("etape", "dt", "regime", "vue", "vue_active", "corps_actifs", "onde_amp", "onde_t",
								 "a_montee", "charges_actives"),
			&NoyauRemontee::etape);
	ClassDB::bind_method(D_METHOD("get_paquets"), &NoyauRemontee::get_paquets);
	ClassDB::bind_method(D_METHOD("fleche_en", "d", "montee"), &NoyauRemontee::fleche_en);
	ClassDB::bind_method(D_METHOD("points", "s"), &NoyauRemontee::points);
	ClassDB::bind_method(D_METHOD("touches", "pylones_d", "voie"), &NoyauRemontee::touches);
	ClassDB::bind_method(D_METHOD("en_gare"), &NoyauRemontee::en_gare);
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

PackedFloat64Array NoyauRemontee::etape(double dt, double regime, const Vector3 &vue, bool vue_active, bool corps_actifs,
		double onde_amp, double onde_t, double a_montee, bool charges_actives) {
	const size_t n = s_veh.size();
	d_onde_amp = onde_amp;
	d_onde_t = onde_t;
	d_a_montee = a_montee;
	// 1. avance sur la boucle (profil de vitesse des lanceurs)
	for (size_t i = 0; i < n; i++) {
		double s = s_veh[i] + vitesse_en(s_veh[i]) * regime * dt;
		s = std::fmod(s, longueur);
		if (s < 0.0) {
			s += longueur;
		}
		s_veh[i] = s;
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
		double dt_i = dt;
		if (vue_active) {
			const double dx = p.x - vue.x, dz = p.z - vue.z;
			const double d2 = dx * dx + dz * dz;
			proche = d2 < 60.0 * 60.0;
			if (d2 > 700.0 * 700.0) {
				continue;
			}
			if (d2 > 250.0 * 250.0) {
				if ((i + tour) % 4 != 0) {
					continue;
				}
				dt_i = 0.0;
			}
		}
		const Zone z = zone(s);
		if (z.idx >= 0) {
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
		v->set_transform(Transform3D(bv, p));
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
					for (int k = 0; k < ns; k++) {
						const double ddphi = -(g2 / L) * std::sin(phi[i]) - (-la.z / L) * std::cos(phi[i]) - 2.0 * zeta * w0 * dphi[i];
						const double ddpsi = -(g2 / L) * std::sin(psi[i]) - (la.x / L) * std::cos(psi[i]) - 2.0 * zeta * w0 * dpsi[i];
						dphi[i] += ddphi * h;
						dpsi[i] += ddpsi * h;
						phi[i] += dphi[i] * h;
						psi[i] += dpsi[i] * h;
					}
					phi[i] = std::clamp(phi[i], -0.6, 0.6);
					psi[i] = std::clamp(psi[i], -0.6, 0.6);
					susps[i]->set_rotation(Vector3((real_t)phi[i], 0, (real_t)psi[i]));
				}
			}
		}
		// corps de collision (lignes proches), suit le balancement
		if (corps_actifs && proche && corps[i] != nullptr) {
			const Transform3D bal = Transform3D(Basis::from_euler(Vector3((real_t)phi[i], 0, (real_t)(psi[i] * sx))), pv) *
					Transform3D(Basis(), -pv);
			corps[i]->set_transform(Transform3D(b, p) * bal);
		}
		// pièces animées en gare : appel seulement quand la valeur change
		float ouv = 0.0f, gc = 1.0f, porte = 0.0f;
		if (z.idx >= 0) {
			ouv = fixe ? 0.0f : (float)smoothstep(0.0, l_ouverture, std::min(z.x, z.l - z.x));
			const double xh = z_haut[z.idx], xb = z_bas[z.idx];
			gc = (float)(1.0 - std::clamp((z.x - xh) / 2.0, 0.0, 1.0) * std::clamp((xb - z.x) / 2.0, 0.0, 1.0));
			if (cabine) {
				porte = (float)std::clamp((std::min(z.x, z.l - z.x) - l_frein) / 2.0, 0.0, 1.0);
			}
		}
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
	}
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
