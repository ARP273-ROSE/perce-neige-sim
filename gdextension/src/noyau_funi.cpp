#include "noyau_funi.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <cmath>
#include <vector>

using namespace godot;

void NoyauFuni::_bind_methods() {
	ClassDB::bind_method(D_METHOD("tube_cable", "pts", "voie_x", "voie_y", "uv_v", "rayon", "ns"),
			&NoyauFuni::tube_cable);
	ClassDB::bind_method(D_METHOD("set_spline", "noeuds", "pas", "longueur"), &NoyauFuni::set_spline);
	ClassDB::bind_method(D_METHOD("transform_at", "s"), &NoyauFuni::transform_at);
	ClassDB::bind_method(D_METHOD("transforms_at", "s"), &NoyauFuni::transforms_at);
	ClassDB::bind_method(D_METHOD("set_croisement", "debut", "fin", "decal_max"), &NoyauFuni::set_croisement);
	ClassDB::bind_method(D_METHOD("passing_loop_offset", "s", "cote"), &NoyauFuni::passing_loop_offset);
	ClassDB::bind_method(D_METHOD("poses_rame", "s_pos", "cote", "nb_voitures", "long_voiture", "demi_bogie"),
			&NoyauFuni::poses_rame);
}

void NoyauFuni::set_croisement(double debut, double fin, double decal_max) {
	croise_debut = debut;
	croise_fin = fin;
	croise_max = decal_max;
}

double NoyauFuni::passing_loop_offset(double s, double cote) const {
	if (s <= croise_debut || s >= croise_fin) {
		return 0.0;
	}
	const double k = (s - croise_debut) / (croise_fin - croise_debut);
	const double s_pi = std::sin(3.14159265358979323846 * k);
	return cote * croise_max * (s_pi * s_pi);
}

// Cabin._cabin_world_pos
Vector3 NoyauFuni::position_rame(double s, double cote) const {
	const Transform3D xf = transform_at(s);
	return xf.origin + xf.basis.get_column(0) * real_t(passing_loop_offset(s, cote));
}

// Cabin._xform_from
Transform3D NoyauFuni::repere_caisse(const Vector3 &pos, const Vector3 &tangente) {
	Vector3 right = tangente.cross(Vector3(0, 1, 0)).normalized();
	if (right.length() < 0.01) {
		right = Vector3(1, 0, 0);
	}
	const Vector3 up = right.cross(tangente).normalized();
	Transform3D xf;
	xf.basis = Basis(right, up, -tangente);
	xf.origin = pos + up * real_t(-0.15);
	return xf;
}

Array NoyauFuni::poses_rame(double s_pos, double cote, int nb_voitures, double long_voiture, double demi_bogie) const {
	Array r;
	const double eps = 1.5;
	const double s_prev = s_pos - eps > 0.0 ? s_pos - eps : 0.0;
	const double s_next = s_pos + eps < longueur ? s_pos + eps : longueur;
	const Vector3 pos_cur = position_rame(s_pos, cote);
	const Vector3 pos_prev = position_rame(s_prev, cote);
	const Vector3 pos_next = position_rame(s_next, cote);
	Vector3 traj = (pos_next - pos_prev).normalized();
	if (traj.length() < 0.5) {
		traj = Vector3(0, 0, -1);
	}
	r.append(repere_caisse(pos_cur, traj));
	for (int idx = 0; idx < nb_voitures; idx++) {
		const double z_c = (double(idx) - double(nb_voitures - 1) * 0.5) * long_voiture;
		double s_car = s_pos - 1.0 * z_c;
		s_car = s_car < 0.0 ? 0.0 : (s_car > longueur ? longueur : s_car);
		const double sa = s_car - demi_bogie;
		const double sb = s_car + demi_bogie;
		const Vector3 p_a = position_rame(sa > 0.0 ? sa : 0.0, cote);
		const Vector3 p_b = position_rame(sb < longueur ? sb : longueur, cote);
		const Vector3 p_c = (p_a + p_b) * real_t(0.5);
		Vector3 tg = (p_b - p_a).normalized();
		if (tg.length() < 0.5) {
			tg = traj;
		}
		r.append(repere_caisse(p_c, tg));
	}
	return r;
}

void NoyauFuni::set_spline(const PackedVector3Array &p_noeuds, double p_pas, double p_longueur) {
	noeuds = p_noeuds;
	pas = p_pas;
	longueur = p_longueur;
}

// Même calcul que le GDScript, opérations dans le même ordre : scalaires en double,
// convertis en real_t au produit avec un Vector3 (comme les opérateurs de Variant).
Transform3D NoyauFuni::transform_at(double s) const {
	s = s < 0.0 ? 0.0 : (s > longueur ? longueur : s);
	const int64_t nn = noeuds.size();
	if (nn < 4) {
		return Transform3D();
	}
	const double u = s / pas + 1.0;
	int64_t i = int64_t(u);
	if (i > nn - 3) {
		i = nn - 3;
	}
	const double t = u - double(i);
	const Vector3 *nd = noeuds.ptr();
	const Vector3 p1 = nd[i];
	const Vector3 d0 = nd[i - 1] - p1;
	const Vector3 d2 = nd[i + 1] - p1;
	const Vector3 d3 = nd[i + 2] - p1;
	const double t2 = t * t;
	const double t3 = t2 * t;
	const double mt = 1.0 - t;
	const Vector3 pos = p1 + (d0 * real_t(mt * mt * mt) + d2 * real_t(-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0)
			+ d3 * real_t(t3)) / real_t(6.0);
	const Vector3 tangent = (d0 * real_t(-mt * mt) + d2 * real_t(-3.0 * t2 + 2.0 * t + 1.0)
			+ d3 * real_t(t2)).normalized();
	Vector3 right = tangent.cross(Vector3(0, 1, 0)).normalized();
	if (right.length() < 0.01) {
		right = Vector3(1, 0, 0);
	}
	const Vector3 up = right.cross(tangent).normalized();
	Transform3D tf;
	tf.basis = Basis(right, up, -tangent);
	tf.origin = pos;
	return tf;
}

Array NoyauFuni::transforms_at(const PackedFloat32Array &s) const {
	Array r;
	r.resize(s.size());
	for (int64_t k = 0; k < s.size(); k++) {
		r[k] = transform_at(s[k]);
	}
	return r;
}

Array NoyauFuni::tube_cable(const PackedVector3Array &pts, const PackedVector3Array &voie_x,
		const PackedVector3Array &voie_y, const PackedFloat32Array &uv_v, double rayon, int ns) const {
	const int64_t n = pts.size();
	if (n < 2 || ns < 1 || voie_x.size() != n || voie_y.size() != n || uv_v.size() != n) {
		return Array();
	}
	const int64_t na = ns + 1;
	std::vector<Vector3> pos(n * na), nor(n * na);
	std::vector<Vector2> uv(n * na);
	const double tau = 6.28318530717958647692;
	for (int64_t i = 0; i < n; i++) {
		const Vector3 p0 = pts[i > 0 ? i - 1 : 0];
		const Vector3 p1 = pts[i + 1 < n ? i + 1 : n - 1];
		const Vector3 t = (p1 - p0).normalized();
		const Vector3 bvx = voie_x[i];
		const Vector3 bvy = voie_y[i];
		const Vector3 bx = (bvx - t * bvx.dot(t)).normalized();
		Vector3 by = bvy - t * bvy.dot(t);
		by = (by - bx * by.dot(bx)).normalized();
		for (int64_t j = 0; j < na; j++) {
			const double ph = tau * double(j) / double(ns);
			const Vector3 nn = bx * real_t(std::cos(ph)) + by * real_t(std::sin(ph));
			pos[i * na + j] = pts[i] + nn * real_t(rayon);
			nor[i * na + j] = nn;
			uv[i * na + j] = Vector2(real_t(double(j) / double(ns)), uv_v[i]);
		}
	}
	// sens des faces décidé sur le premier triangle, comme le GDScript
	const Vector3 a = pos[0], b = pos[na], c = pos[na + 1];
	const double g = (b - a).cross(c - a).dot(nor[0] + nor[na] + nor[na + 1]);
	const bool direct = g < 0.0;
	const int64_t nv = (n - 1) * ns * 6;
	PackedVector3Array v_out, n_out;
	PackedVector2Array uv_out;
	v_out.resize(nv);
	n_out.resize(nv);
	uv_out.resize(nv);
	Vector3 *vp = v_out.ptrw();
	Vector3 *np = n_out.ptrw();
	Vector2 *up = uv_out.ptrw();
	int64_t k = 0;
	for (int64_t i = 0; i + 1 < n; i++) {
		const int64_t r0 = i * na, r1 = (i + 1) * na;
		for (int64_t j = 0; j < ns; j++) {
			int64_t q[6];
			if (direct) {
				q[0] = r0 + j; q[1] = r1 + j; q[2] = r1 + j + 1;
				q[3] = r0 + j; q[4] = r1 + j + 1; q[5] = r0 + j + 1;
			} else {
				q[0] = r0 + j; q[1] = r1 + j + 1; q[2] = r1 + j;
				q[3] = r0 + j; q[4] = r0 + j + 1; q[5] = r1 + j + 1;
			}
			for (int e = 0; e < 6; e++) {
				vp[k] = pos[q[e]];
				np[k] = nor[q[e]];
				up[k] = uv[q[e]];
				k++;
			}
		}
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = v_out;
	arrays[Mesh::ARRAY_NORMAL] = n_out;
	arrays[Mesh::ARRAY_TEX_UV] = uv_out;
	return arrays;
}
