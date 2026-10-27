#include "outils_maillage.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

using namespace godot;

void OutilsMaillage::_bind_methods() {
	ClassDB::bind_method(D_METHOD("fusionner", "surfaces", "transformations"), &OutilsMaillage::fusionner);
}

Array OutilsMaillage::fusionner(const Array &surfaces, const Array &transformations) const {
	const int64_t ns = surfaces.size();
	// tailles totales (et présence de chaque attribut)
	int64_t nv = 0, nn = 0, nt = 0, nc = 0, nu = 0, nu2 = 0, ni = 0;
	bool a_n = false, a_t = false, a_c = false, a_u = false, a_u2 = false, a_i = false;
	for (int64_t k = 0; k < ns; k++) {
		const Array a = surfaces[k];
		nv += PackedVector3Array(a[Mesh::ARRAY_VERTEX]).size();
		if (a[Mesh::ARRAY_NORMAL].get_type() != Variant::NIL) {
			a_n = true;
			nn += PackedVector3Array(a[Mesh::ARRAY_NORMAL]).size();
		}
		if (a[Mesh::ARRAY_TANGENT].get_type() != Variant::NIL) {
			a_t = true;
			nt += PackedFloat32Array(a[Mesh::ARRAY_TANGENT]).size();
		}
		if (a[Mesh::ARRAY_COLOR].get_type() != Variant::NIL) {
			a_c = true;
			nc += PackedColorArray(a[Mesh::ARRAY_COLOR]).size();
		}
		if (a[Mesh::ARRAY_TEX_UV].get_type() != Variant::NIL) {
			a_u = true;
			nu += PackedVector2Array(a[Mesh::ARRAY_TEX_UV]).size();
		}
		if (a[Mesh::ARRAY_TEX_UV2].get_type() != Variant::NIL) {
			a_u2 = true;
			nu2 += PackedVector2Array(a[Mesh::ARRAY_TEX_UV2]).size();
		}
		if (a[Mesh::ARRAY_INDEX].get_type() != Variant::NIL) {
			a_i = true;
			ni += PackedInt32Array(a[Mesh::ARRAY_INDEX]).size();
		}
	}
	PackedVector3Array dv, dn;
	PackedFloat32Array dt;
	PackedColorArray dc;
	PackedVector2Array du, du2;
	PackedInt32Array di;
	dv.resize(nv);
	dn.resize(nn);
	dt.resize(nt);
	dc.resize(nc);
	du.resize(nu);
	du2.resize(nu2);
	di.resize(ni);
	Vector3 *pv = dv.ptrw();
	Vector3 *pn = dn.ptrw();
	float *pt = dt.ptrw();
	Color *pc = dc.ptrw();
	Vector2 *pu = du.ptrw();
	Vector2 *pu2 = du2.ptrw();
	int32_t *pi = di.ptrw();
	int64_t kv = 0, kn = 0, kt = 0, kc = 0, ku = 0, ku2 = 0, ki = 0;
	for (int64_t k = 0; k < ns; k++) {
		const Array a = surfaces[k];
		const Transform3D xf = transformations[k];
		const int64_t n0 = kv;
		const PackedVector3Array v = a[Mesh::ARRAY_VERTEX];
		const Vector3 *sv = v.ptr();
		for (int64_t i = 0; i < v.size(); i++) {
			pv[kv++] = xf.xform(sv[i]);
		}
		if (a[Mesh::ARRAY_NORMAL].get_type() != Variant::NIL) {
			const Basis nb = xf.basis.inverse().transposed();
			const PackedVector3Array s = a[Mesh::ARRAY_NORMAL];
			const Vector3 *ss = s.ptr();
			for (int64_t i = 0; i < s.size(); i++) {
				pn[kn++] = nb.xform(ss[i]).normalized();
			}
		}
		if (a[Mesh::ARRAY_TANGENT].get_type() != Variant::NIL) {
			const PackedFloat32Array s = a[Mesh::ARRAY_TANGENT];
			const float *ss = s.ptr();
			for (int64_t i = 0; i + 3 < s.size(); i += 4) {
				const Vector3 t3 = xf.basis.xform(Vector3(ss[i], ss[i + 1], ss[i + 2])).normalized();
				pt[kt++] = t3.x;
				pt[kt++] = t3.y;
				pt[kt++] = t3.z;
				pt[kt++] = ss[i + 3];
			}
		}
		if (a[Mesh::ARRAY_COLOR].get_type() != Variant::NIL) {
			const PackedColorArray s = a[Mesh::ARRAY_COLOR];
			for (int64_t i = 0; i < s.size(); i++) {
				pc[kc++] = s[i];
			}
		}
		if (a[Mesh::ARRAY_TEX_UV].get_type() != Variant::NIL) {
			const PackedVector2Array s = a[Mesh::ARRAY_TEX_UV];
			const Vector2 *ss = s.ptr();
			for (int64_t i = 0; i < s.size(); i++) {
				pu[ku++] = ss[i];
			}
		}
		if (a[Mesh::ARRAY_TEX_UV2].get_type() != Variant::NIL) {
			const PackedVector2Array s = a[Mesh::ARRAY_TEX_UV2];
			const Vector2 *ss = s.ptr();
			for (int64_t i = 0; i < s.size(); i++) {
				pu2[ku2++] = ss[i];
			}
		}
		if (a[Mesh::ARRAY_INDEX].get_type() != Variant::NIL) {
			const PackedInt32Array s = a[Mesh::ARRAY_INDEX];
			const int32_t *ss = s.ptr();
			for (int64_t i = 0; i < s.size(); i++) {
				pi[ki++] = ss[i] + int32_t(n0);
			}
		}
	}
	Array out;
	out.resize(Mesh::ARRAY_MAX);
	out[Mesh::ARRAY_VERTEX] = dv;
	if (a_n) {
		out[Mesh::ARRAY_NORMAL] = dn;
	}
	if (a_t) {
		out[Mesh::ARRAY_TANGENT] = dt;
	}
	if (a_c) {
		out[Mesh::ARRAY_COLOR] = dc;
	}
	if (a_u) {
		out[Mesh::ARRAY_TEX_UV] = du;
	}
	if (a_u2) {
		out[Mesh::ARRAY_TEX_UV2] = du2;
	}
	if (a_i) {
		out[Mesh::ARRAY_INDEX] = di;
	}
	return out;
}
