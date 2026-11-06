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
	// Surfaces de formats différents (une copie gardée sans tangentes, une autre relue sur la carte avec) :
	// un attribut présent sur une partie seulement des surfaces est complété, pour les autres, par une valeur
	// neutre, et une surface sans indices reçoit 0..n-1 — sinon les tableaux n'ont plus la longueur des
	// sommets et le rendu refuse la surface entière (pièces « galva » des pylônes de l'Olympique, 06/11/2026).
	// Les tangentes seulement si toutes en ont (sans tangentes, le rendu les déduit des normales).
	const int64_t ns = surfaces.size();
	int64_t nv = 0, ni = 0;
	bool a_n = false, a_t = true, a_c = false, a_u = false, a_u2 = false, a_i = false;
	for (int64_t k = 0; k < ns; k++) {
		const Array a = surfaces[k];
		const int64_t n = PackedVector3Array(a[Mesh::ARRAY_VERTEX]).size();
		nv += n;
		a_n = a_n || a[Mesh::ARRAY_NORMAL].get_type() != Variant::NIL;
		a_t = a_t && a[Mesh::ARRAY_TANGENT].get_type() != Variant::NIL;
		a_c = a_c || a[Mesh::ARRAY_COLOR].get_type() != Variant::NIL;
		a_u = a_u || a[Mesh::ARRAY_TEX_UV].get_type() != Variant::NIL;
		a_u2 = a_u2 || a[Mesh::ARRAY_TEX_UV2].get_type() != Variant::NIL;
		if (a[Mesh::ARRAY_INDEX].get_type() != Variant::NIL) {
			a_i = true;
			ni += PackedInt32Array(a[Mesh::ARRAY_INDEX]).size();
		} else {
			ni += n;
		}
	}
	a_t = a_t && ns > 0;
	PackedVector3Array dv, dn;
	PackedFloat32Array dt;
	PackedColorArray dc;
	PackedVector2Array du, du2;
	PackedInt32Array di;
	dv.resize(nv);
	dn.resize(a_n ? nv : 0);
	dt.resize(a_t ? nv * 4 : 0);
	dc.resize(a_c ? nv : 0);
	du.resize(a_u ? nv : 0);
	du2.resize(a_u2 ? nv : 0);
	di.resize(a_i ? ni : 0);
	Vector3 *pv = dv.ptrw();
	Vector3 *pn = dn.ptrw();
	float *pt = dt.ptrw();
	Color *pc = dc.ptrw();
	Vector2 *pu = du.ptrw();
	Vector2 *pu2 = du2.ptrw();
	int32_t *pi = di.ptrw();
	int64_t kv = 0, ki = 0;
	for (int64_t k = 0; k < ns; k++) {
		const Array a = surfaces[k];
		const Transform3D xf = transformations[k];
		const int64_t n0 = kv;
		const PackedVector3Array v = a[Mesh::ARRAY_VERTEX];
		const int64_t n = v.size();
		const Vector3 *sv = v.ptr();
		for (int64_t i = 0; i < n; i++) {
			pv[n0 + i] = xf.xform(sv[i]);
		}
		if (a_n) {
			const Basis nb = xf.basis.inverse().transposed();
			const PackedVector3Array s = a[Mesh::ARRAY_NORMAL];
			const Vector3 *ss = s.ptr();
			const Vector3 haut = nb.xform(Vector3(0, 1, 0)).normalized();
			for (int64_t i = 0; i < n; i++) {
				pn[n0 + i] = i < s.size() ? nb.xform(ss[i]).normalized() : haut;
			}
		}
		if (a_t) {
			const PackedFloat32Array s = a[Mesh::ARRAY_TANGENT];
			const float *ss = s.ptr();
			for (int64_t i = 0; i < n; i++) {
				const bool ok = i * 4 + 3 < s.size();
				const Vector3 t3 = xf.basis.xform(ok ? Vector3(ss[i * 4], ss[i * 4 + 1], ss[i * 4 + 2]) : Vector3(1, 0, 0)).normalized();
				pt[(n0 + i) * 4] = t3.x;
				pt[(n0 + i) * 4 + 1] = t3.y;
				pt[(n0 + i) * 4 + 2] = t3.z;
				pt[(n0 + i) * 4 + 3] = ok ? ss[i * 4 + 3] : 1.0f;
			}
		}
		if (a_c) {
			const PackedColorArray s = a[Mesh::ARRAY_COLOR];
			const Color *ss = s.ptr();
			for (int64_t i = 0; i < n; i++) {
				pc[n0 + i] = i < s.size() ? ss[i] : Color(1, 1, 1, 1);
			}
		}
		if (a_u) {
			const PackedVector2Array s = a[Mesh::ARRAY_TEX_UV];
			const Vector2 *ss = s.ptr();
			for (int64_t i = 0; i < n; i++) {
				pu[n0 + i] = i < s.size() ? ss[i] : Vector2();
			}
		}
		if (a_u2) {
			const PackedVector2Array s = a[Mesh::ARRAY_TEX_UV2];
			const Vector2 *ss = s.ptr();
			for (int64_t i = 0; i < n; i++) {
				pu2[n0 + i] = i < s.size() ? ss[i] : Vector2();
			}
		}
		if (a_i) {
			if (a[Mesh::ARRAY_INDEX].get_type() != Variant::NIL) {
				const PackedInt32Array s = a[Mesh::ARRAY_INDEX];
				const int32_t *ss = s.ptr();
				for (int64_t i = 0; i < s.size(); i++) {
					pi[ki++] = ss[i] + int32_t(n0);
				}
			} else {
				for (int64_t i = 0; i < n; i++) {
					pi[ki++] = int32_t(n0 + i);
				}
			}
		}
		kv += n;
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
		di.resize(ki);
		out[Mesh::ARRAY_INDEX] = di;
	}
	return out;
}
