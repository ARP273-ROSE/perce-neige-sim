#include "outils_voie.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <vector>

using namespace godot;

void OutilsVoie::_bind_methods() {
	ClassDB::bind_method(D_METHOD("tube_brin", "centres", "droites", "hauts", "s", "d", "ns", "rayon", "dmax"),
			&OutilsVoie::tube_brin);
	ClassDB::bind_method(D_METHOD("extruder_bandes", "origines", "droites", "hauts", "cx", "s", "bandes"),
			&OutilsVoie::extruder_bandes);
}

namespace {

// _pt de TrackBuilder : origine + droite × dx + haut × dy. dx et dy sont des flottants de GDScript (doubles),
// ramenés en réels simples au produit par le vecteur, comme Vector3 * float dans GDScript.
inline Vector3 point(const Vector3 &o, const Vector3 &r, const Vector3 &u, double dx, double dy) {
	return (o + r * (real_t)dx) + u * (real_t)dy;
}

// _emit_quad_strip : deux triangles (00, 10, 11) et (00, 11, 01).
inline void quad(Vector3 *&pv, Vector2 *&pu, const Vector3 &p00, const Vector3 &p01, const Vector3 &p10,
		const Vector3 &p11, const Vector2 &uv00, const Vector2 &uv01, const Vector2 &uv10, const Vector2 &uv11) {
	*pu++ = uv00;
	*pv++ = p00;
	*pu++ = uv10;
	*pv++ = p10;
	*pu++ = uv11;
	*pv++ = p11;
	*pu++ = uv00;
	*pv++ = p00;
	*pu++ = uv11;
	*pv++ = p11;
	*pu++ = uv01;
	*pv++ = p01;
}

} // namespace

Array OutilsVoie::extruder_bandes(const PackedVector3Array &origines, const PackedVector3Array &droites,
		const PackedVector3Array &hauts, const PackedFloat64Array &cx, const PackedFloat64Array &s,
		const PackedFloat64Array &bandes) const {
	const int64_t n = origines.size();
	const int64_t nb = bandes.size() / 4;
	PackedVector3Array dv;
	PackedVector2Array du;
	const int64_t nv = (n > 1 ? n - 1 : 0) * nb * 18;
	dv.resize(nv);
	du.resize(nv);
	Vector3 *pv = dv.ptrw();
	Vector2 *pu = du.ptrw();
	const Vector3 *po = origines.ptr();
	const Vector3 *pr = droites.ptr();
	const Vector3 *ph = hauts.ptr();
	const double *pcx = cx.ptr();
	const double *ps = s.ptr();
	const double *pb = bandes.ptr();
	for (int64_t i = 1; i < n; i++) {
		const Vector3 &p0 = po[i - 1], &r0 = pr[i - 1], &u0 = ph[i - 1];
		const Vector3 &p1 = po[i], &r1 = pr[i], &u1 = ph[i];
		const double c0 = pcx[i - 1], c1 = pcx[i];
		const real_t v0 = (real_t)ps[i - 1], v1 = (real_t)ps[i];
		for (int64_t b = 0; b < nb; b++) {
			const double y_lo = pb[b * 4], y_hi = pb[b * 4 + 1], w_lo = pb[b * 4 + 2], w_hi = pb[b * 4 + 3];
			const Vector3 a00 = point(p0, r0, u0, c0 - w_lo, y_lo);
			const Vector3 a01 = point(p0, r0, u0, c0 + w_lo, y_lo);
			const Vector3 a10 = point(p0, r0, u0, c0 + w_hi, y_hi);
			const Vector3 a11 = point(p0, r0, u0, c0 - w_hi, y_hi);
			const Vector3 b00 = point(p1, r1, u1, c1 - w_lo, y_lo);
			const Vector3 b01 = point(p1, r1, u1, c1 + w_lo, y_lo);
			const Vector3 b10 = point(p1, r1, u1, c1 + w_hi, y_hi);
			const Vector3 b11 = point(p1, r1, u1, c1 - w_hi, y_hi);
			// face gauche
			quad(pv, pu, a00, a11, b00, b11, Vector2(0.0, v0), Vector2((real_t)0.1, v0), Vector2(0.0, v1),
					Vector2((real_t)0.1, v1));
			// face droite
			quad(pv, pu, a01, b01, a10, b10, Vector2(0.0, v0), Vector2(0.0, v1), Vector2((real_t)0.1, v0),
					Vector2((real_t)0.1, v1));
			// dessus
			quad(pv, pu, a11, a10, b11, b10, Vector2(0.0, v0), Vector2(1.0, v0), Vector2(0.0, v1), Vector2(1.0, v1));
		}
	}
	Array r;
	r.append(dv);
	r.append(du);
	return r;
}

Array OutilsVoie::tube_brin(const PackedVector3Array &centres, const PackedVector3Array &droites,
		const PackedVector3Array &hauts, const PackedFloat64Array &s, const PackedFloat64Array &d, int64_t ns,
		double rayon, double dmax) const {
	const int64_t nr = centres.size();
	const int64_t na = ns + 1;
	// (PackedFloat32Array du GDScript : cos et sin du moteur, rangés en réels simples)
	std::vector<float> cs(na), sn(na);
	for (int64_t k = 0; k < na; k++) {
		const double a = double(k) / double(ns) * Math_TAU;
		cs[k] = (float)UtilityFunctions::cos(a);
		sn[k] = (float)UtilityFunctions::sin(a);
	}
	PackedVector3Array vtx, nrm;
	PackedVector2Array uv, uv2;
	PackedColorArray col;
	PackedInt32Array idx;
	vtx.resize(nr * na);
	nrm.resize(nr * na);
	uv.resize(nr * na);
	uv2.resize(nr * na);
	col.resize(nr * na);
	idx.resize(nr > 1 ? (nr - 1) * ns * 6 : 0);
	Vector3 *wv = vtx.ptrw();
	Vector3 *wn = nrm.ptrw();
	Vector2 *wu = uv.ptrw();
	Vector2 *wu2 = uv2.ptrw();
	Color *wc = col.ptrw();
	int32_t *wi = idx.ptrw();
	const real_t rr = (real_t)rayon;
	int64_t w = 0;
	for (int64_t i = 0; i < nr; i++) {
		const Vector3 c = centres[i];
		const Vector3 r = droites[i];
		const Vector3 u = hauts[i];
		const real_t v_uv = (real_t)(s[i] * 2.0);
		const Vector2 dd = Vector2((real_t)d[i], (real_t)(d[i] / dmax));
		const Color cl = Color((float)(0.5 + 0.5 * (double)r.x), (float)(0.5 + 0.5 * (double)r.y), (float)(0.5 + 0.5 * (double)r.z));
		for (int64_t k = 0; k < na; k++) {
			const Vector3 n = r * cs[k] + u * sn[k];
			wv[w] = c + n * rr;
			wn[w] = -n.normalized();
			wu[w] = Vector2((real_t)(double(k) / double(ns)), v_uv);
			wu2[w] = dd;
			wc[w] = cl;
			w++;
		}
	}
	int64_t q = 0;
	for (int64_t i = 0; i < nr - 1; i++) {
		const int32_t b0 = (int32_t)(i * na);
		const int32_t b1 = (int32_t)(b0 + na);
		for (int32_t k = 0; k < ns; k++) {
			wi[q++] = b0 + k;
			wi[q++] = b1 + k;
			wi[q++] = b1 + k + 1;
			wi[q++] = b0 + k;
			wi[q++] = b1 + k + 1;
			wi[q++] = b0 + k + 1;
		}
	}
	Array res;
	res.append(vtx);
	res.append(nrm);
	res.append(uv);
	res.append(uv2);
	res.append(col);
	res.append(idx);
	return res;
}
