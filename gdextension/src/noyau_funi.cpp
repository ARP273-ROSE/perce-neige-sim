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
