// Fusion des maillages (MeshMerge, mesh_merge.gd) : parcours du sous-arbre, regroupement des surfaces par
// matériau et retrait des sources, en C++. En GDScript, parcours et regroupement faisaient plus de la moitié
// du temps de fusion (banc de fluidité du 14/11/2026 : 4,3 s sur 7,1 s, ~12 µs par pièce). Mêmes tests, même
// ordre de parcours, mêmes clés de groupe (même format que le GDScript) : les groupes, donc les maillages
// fusionnés, sont identiques. Les copies côté processeur (MeshMerge._cpu) sont lues ici ; les autres cas
// (primitives, relectures) repassent par MeshMerge.tableaux, en GDScript.
#include "outils_maillage.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/base_material3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/cylinder_mesh.hpp>
#include <godot_cpp/classes/point_mesh.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/torus_mesh.hpp>
#include <godot_cpp/classes/primitive_mesh.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/weak_ref.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <utility>
#include <vector>

using namespace godot;

namespace {

const StringName &meta_sans_fusion() {
	static const StringName s("sans_fusion");
	return s;
}

Ref<Material> materiau_de(MeshInstance3D *mi, const Ref<Mesh> &mesh, int32_t si) {
	Ref<Material> m = mi->get_material_override();
	if (m.is_valid()) {
		return m;
	}
	m = mi->get_surface_override_material(si);
	if (m.is_null()) {
		m = mesh->surface_get_material(si);
	}
	return m;
}

bool opaque(const Ref<Material> &m) {
	BaseMaterial3D *b = Object::cast_to<BaseMaterial3D>(m.ptr());
	if (b == nullptr) {
		return false;
	}
	return b->get_transparency() == BaseMaterial3D::TRANSPARENCY_DISABLED && (double)b->get_albedo().a >= 0.999 &&
			b->get_next_pass().is_null();
}

bool triangles(const Ref<Mesh> &mesh, int32_t si) {
	ArrayMesh *am = Object::cast_to<ArrayMesh>(mesh.ptr());
	if (am != nullptr) {
		return am->surface_get_primitive_type(si) == Mesh::PRIMITIVE_TRIANGLES;
	}
	return Object::cast_to<PrimitiveMesh>(mesh.ptr()) != nullptr && Object::cast_to<PointMesh>(mesh.ptr()) == nullptr;
}

// MeshMerge.tableaux : la copie gardée (sous le verrou) si elle existe, sinon le repli GDScript.
struct Lecteur {
	const Dictionary &cpu;
	Mutex *verrou;
	const Callable &repli;

	Array tableaux(const Ref<Mesh> &mesh, int32_t si) const {
		if (verrou != nullptr) {
			verrou->lock();
		}
		Array r;
		bool trouve = false;
		const Variant id = (int64_t)mesh->get_instance_id();
		if (cpu.has(id)) {
			const Array e = cpu[id];
			Ref<WeakRef> w = e[0];
			if (w.is_valid() && (Object *)w->get_ref() == mesh.ptr()) {
				const Array l = e[1];
				if (si < l.size() && l[si].get_type() != Variant::NIL) {
					r = l[si];
					trouve = true;
				}
			}
		}
		if (verrou != nullptr) {
			verrou->unlock();
		}
		if (trouve) {
			return r;
		}
		return repli.call(mesh, si);
	}
};

// MeshMerge._format : bits des attributs présents (normale, tangente, couleur, UV, UV2, index).
int64_t format_de(const Ref<Mesh> &mesh, int32_t si, const Lecteur &lec) {
	ArrayMesh *am = Object::cast_to<ArrayMesh>(mesh.ptr());
	static const int64_t bits[6] = { Mesh::ARRAY_FORMAT_NORMAL, Mesh::ARRAY_FORMAT_TANGENT, Mesh::ARRAY_FORMAT_COLOR,
		Mesh::ARRAY_FORMAT_TEX_UV, Mesh::ARRAY_FORMAT_TEX_UV2, Mesh::ARRAY_FORMAT_INDEX };
	static const int attrs[6] = { Mesh::ARRAY_NORMAL, Mesh::ARRAY_TANGENT, Mesh::ARRAY_COLOR, Mesh::ARRAY_TEX_UV,
		Mesh::ARRAY_TEX_UV2, Mesh::ARRAY_INDEX };
	int64_t f = 0;
	if (am != nullptr) {
		const int64_t fm = (int64_t)am->surface_get_format(si);
		for (int i = 0; i < 6; i++) {
			if (fm & bits[i]) {
				f |= int64_t(1) << i;
			}
		}
		return f;
	}
	const Array a = lec.tableaux(mesh, si);
	for (int i = 0; i < 6; i++) {
		if (a[attrs[i]].get_type() != Variant::NIL) {
			f |= int64_t(1) << i;
		}
	}
	return f;
}

// MeshMerge._collect (chemin sans palette) : surfaces de `mi` ajoutées à leur groupe.
void collecter_un(MeshInstance3D *mi, const Transform3D &xf, Dictionary &groups, const Lecteur &lec) {
	Ref<Mesh> mesh = mi->get_mesh();
	if (mesh.is_null() || mi->get_material_overlay().is_valid() || mi->get_visibility_range_begin() > 0.0 ||
			mi->get_script().get_type() != Variant::NIL || xf.basis.determinant() <= 0.0 || mi->get_skin().is_valid()) {
		return;
	}
	ArrayMesh *am = Object::cast_to<ArrayMesh>(mesh.ptr());
	if (am != nullptr && am->get_blend_shape_count() > 0) {
		return;
	}
	const int32_t ns = mesh->get_surface_count();
	std::vector<Ref<Material>> mats;
	mats.reserve(ns);
	for (int32_t si = 0; si < ns; si++) {
		Ref<Material> m = materiau_de(mi, mesh, si);
		if (m.is_null() || !opaque(m) || !triangles(mesh, si)) {
			return; // une surface non fusionnable → l'objet reste entier
		}
		mats.push_back(m);
	}
	const int64_t ombre = (int64_t)mi->get_cast_shadows_setting();
	const double portee = mi->get_visibility_range_end();
	static const String fmt_cle("%d_%d_%d_%.1f");
	static const String k_mat("mat"), k_acc("acc"), k_n("n"), k_src("src"), k_shadow("shadow"), k_range("range"),
			k_surfaces("surfaces"), k_xfs("xfs");
	for (int32_t si = 0; si < ns; si++) {
		const int64_t f = format_de(mesh, si, lec);
		Array args;
		args.push_back((int64_t)mats[si]->get_instance_id());
		args.push_back(f);
		args.push_back(ombre);
		args.push_back(portee);
		const String cle = fmt_cle % args;
		if (!groups.has(cle)) {
			Dictionary g;
			g[k_mat] = mats[si];
			g[k_acc] = Dictionary();
			g[k_n] = 0;
			g[k_src] = Array();
			g[k_shadow] = ombre;
			g[k_range] = portee;
			groups[cle] = g;
		}
		Dictionary g = groups[cle];
		Dictionary acc = g[k_acc];
		if (!acc.has(k_surfaces)) {
			acc[k_surfaces] = Array();
			acc[k_xfs] = Array();
		}
		Array surfaces = acc[k_surfaces];
		Array xfs = acc[k_xfs];
		surfaces.push_back(lec.tableaux(mesh, si));
		xfs.push_back(xf);
		g[k_n] = (int64_t)g[k_n] + 1;
		Array src = g[k_src];
		src.push_back(mi);
	}
}

} // namespace

Array OutilsMaillage::parcourir(Node3D *root, const Array &keep) const {
	Array r;
	if (root == nullptr) {
		return r;
	}
	std::vector<std::pair<Node *, Transform3D>> pile;
	pile.emplace_back(root, Transform3D());
	while (!pile.empty()) {
		const std::pair<Node *, Transform3D> e = pile.back();
		pile.pop_back();
		Node *node = e.first;
		const int32_t nc = node->get_child_count();
		for (int32_t i = 0; i < nc; i++) {
			Node *c = node->get_child(i);
			Node3D *c3 = Object::cast_to<Node3D>(c);
			if (c3 == nullptr || keep.has(c)) {
				continue;
			}
			const Transform3D cxf = e.second * c3->get_transform();
			if (!c3->is_visible()) {
				continue;
			}
			if (Object::cast_to<MeshInstance3D>(c) != nullptr && !c->has_meta(meta_sans_fusion())) {
				Array p;
				p.push_back(c);
				p.push_back(cxf);
				p.push_back((int64_t)c->get_instance_id()); // (validité vérifiée par collecter, sans déréférencer)
				r.push_back(p);
			}
			// un nœud à script peut s'animer lui-même : on ne descend pas
			if (c->get_script().get_type() == Variant::NIL) {
				pile.emplace_back(c, cxf);
			}
		}
	}
	return r;
}

int64_t OutilsMaillage::collecter(const Array &elements, int64_t debut, int64_t budget_us, Dictionary groups,
		const Dictionary &cpu, const Variant &verrou, const Callable &repli) const {
	Mutex *mx = Object::cast_to<Mutex>((Object *)verrou);
	const Lecteur lec{ cpu, mx, repli };
	Time *horloge = Time::get_singleton();
	const uint64_t t0 = horloge->get_ticks_usec();
	const int64_t n = elements.size();
	for (int64_t i = debut; i < n; i++) {
		const Array e = elements[i];
		const int64_t id = e.size() > 2 ? (int64_t)e[2] : (int64_t)((Object *)e[0])->get_instance_id();
		if (UtilityFunctions::is_instance_id_valid(id)) {
			MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(UtilityFunctions::instance_from_id(id));
			if (mi != nullptr) {
				collecter_un(mi, e[1], groups, lec);
			}
		}
		if (budget_us > 0 && int64_t(horloge->get_ticks_usec() - t0) > budget_us) {
			return i + 1;
		}
	}
	return n;
}

void OutilsMaillage::retirer(const Dictionary &done) const {
	const Array cles = done.keys();
	for (int64_t k = 0; k < cles.size(); k++) {
		const Variant v = cles[k];
		MeshInstance3D *mi = Object::cast_to<MeshInstance3D>((Object *)v);
		if (mi == nullptr) {
			continue;
		}
		Ref<Mesh> mesh = mi->get_mesh();
		if (mesh.is_null() || (int64_t)done[v] != (int64_t)mesh->get_surface_count()) {
			continue;
		}
		const bool dans_scene = mi->is_inside_tree();
		Node *parent = mi->get_parent();
		if (parent != nullptr) {
			parent->remove_child(mi);
		}
		// hors de la scène (construction sur un autre fil) : libérée tout de suite (voir _retirer_sources)
		if (dans_scene) {
			mi->queue_free();
		} else {
			memdelete(mi);
		}
	}
}

// --- Triangles des primitives (collisions sans relire la carte) ------------------------------------------------
// PrimitiveMesh.get_mesh_arrays() n'est qu'un surface_get_arrays(0) : relu sur la carte graphique (à l'écran, ~32 ms
// de blocage du fil principal). Les positions et les indices des cylindres, sphères et tores sont recalculés ici
// comme dans le moteur 4.6 (scene/resources/3d/primitive_meshes.cpp : mêmes types float / double, même ordre ;
// sin et cos du moteur pour les calculs en double), retournement des faces compris. Rend la soupe de triangles
// (comme MeshMerge.faces), vide pour une autre primitive.

namespace {

void soupe(const std::vector<Vector3> &pts, std::vector<int> &ix, bool flip, PackedVector3Array &out) {
	if (flip) {
		for (size_t i = 0; i + 2 < ix.size(); i += 3) {
			std::swap(ix[i], ix[i + 1]);
		}
	}
	out.resize((int64_t)ix.size());
	Vector3 *w = out.ptrw();
	for (size_t i = 0; i < ix.size(); i++) {
		w[i] = pts[ix[i]];
	}
}

inline float dsin(double a) { return (float)UtilityFunctions::sin(a); }
inline float dcos(double a) { return (float)UtilityFunctions::cos(a); }

} // namespace

PackedVector3Array OutilsMaillage::faces_primitive(const Ref<PrimitiveMesh> &prim) const {
	PackedVector3Array out;
	std::vector<Vector3> pts;
	std::vector<int> ix;
	if (CylinderMesh *c = Object::cast_to<CylinderMesh>(prim.ptr())) {
		const float top_radius = c->get_top_radius(), bottom_radius = c->get_bottom_radius(), height = c->get_height();
		const int radial_segments = c->get_radial_segments(), rings = c->get_rings();
		int i, j, prevrow = 0, thisrow = 0, point = 0;
		float x, y, z, v, radius;
		for (j = 0; j <= (rings + 1); j++) {
			v = j;
			v /= (rings + 1);
			radius = top_radius + ((bottom_radius - top_radius) * v);
			y = height * v;
			y = (height * 0.5) - y;
			for (i = 0; i <= radial_segments; i++) {
				float u = i;
				u /= radial_segments;
				if (i == radial_segments) {
					x = 0.0;
					z = 1.0;
				} else {
					x = dsin(u * Math_TAU);
					z = dcos(u * Math_TAU);
				}
				pts.push_back(Vector3(x * radius, y, z * radius));
				point++;
				if (i > 0 && j > 0) {
					ix.insert(ix.end(), { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 });
				}
			}
			prevrow = thisrow;
			thisrow = point;
		}
		for (int cap = 0; cap < 2; cap++) {
			const bool haut = cap == 0;
			const float rr = haut ? top_radius : bottom_radius;
			if (!((haut ? c->is_cap_top() : c->is_cap_bottom()) && rr > 0.0)) {
				continue;
			}
			y = height * (haut ? 0.5 : -0.5);
			thisrow = point;
			pts.push_back(Vector3(0.0, y, 0.0));
			point++;
			for (i = 0; i <= radial_segments; i++) {
				float r = i;
				r /= radial_segments;
				if (i == radial_segments) {
					x = 0.0;
					z = 1.0;
				} else {
					x = dsin(r * Math_TAU);
					z = dcos(r * Math_TAU);
				}
				pts.push_back(Vector3(x * rr, y, z * rr));
				point++;
				if (i > 0) {
					if (haut) {
						ix.insert(ix.end(), { thisrow, point - 1, point - 2 });
					} else {
						ix.insert(ix.end(), { thisrow, point - 2, point - 1 });
					}
				}
			}
		}
	} else if (SphereMesh *s = Object::cast_to<SphereMesh>(prim.ptr())) {
		const float radius = s->get_radius(), height = s->get_height();
		const int radial_segments = s->get_radial_segments(), rings = s->get_rings();
		const bool is_hemisphere = s->get_is_hemisphere();
		int i, j, prevrow = 0, thisrow = 0, point = 0;
		float x, y, z;
		const float scale = height / radius * (is_hemisphere ? 1.0 : 0.5);
		for (j = 0; j <= (rings + 1); j++) {
			float v = j;
			float w;
			v /= (rings + 1);
			if (j == (rings + 1)) {
				w = 0.0;
				y = -1.0;
			} else {
				w = dsin(Math_PI * v);
				y = dcos(Math_PI * v);
			}
			for (i = 0; i <= radial_segments; i++) {
				float u = i;
				u /= radial_segments;
				if (i == radial_segments) {
					x = 0.0;
					z = 1.0;
				} else {
					x = dsin(u * Math_TAU);
					z = dcos(u * Math_TAU);
				}
				if (is_hemisphere && y < 0.0) {
					pts.push_back(Vector3(x * radius * w, 0.0, z * radius * w));
				} else {
					pts.push_back(Vector3(x * w, y * scale, z * w) * radius);
				}
				point++;
				if (i > 0 && j > 0) {
					ix.insert(ix.end(), { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 });
				}
			}
			prevrow = thisrow;
			thisrow = point;
		}
	} else if (TorusMesh *t = Object::cast_to<TorusMesh>(prim.ptr())) {
		float min_radius = t->get_inner_radius(), max_radius = t->get_outer_radius();
		const int rings = t->get_rings(), ring_segments = t->get_ring_segments();
		if (min_radius == max_radius) {
			return out;
		}
		if (min_radius > max_radius) {
			std::swap(min_radius, max_radius);
		}
		const float radius = (max_radius - min_radius) * 0.5;
		for (int i = 0; i <= rings; i++) {
			const int prevrow = (i - 1) * (ring_segments + 1);
			const int thisrow = i * (ring_segments + 1);
			const float inci = float(i) / rings;
			const float angi = inci * Math_TAU;
			const Vector2 normali = (i == rings) ? Vector2(0.0, -1.0) : Vector2(-std::sin(angi), -std::cos(angi));
			for (int j = 0; j <= ring_segments; j++) {
				const float incj = float(j) / ring_segments;
				const float angj = incj * Math_TAU;
				const Vector2 normalj = (j == ring_segments) ? Vector2(-1.0, 0.0) : Vector2(-std::cos(angj), std::sin(angj));
				const Vector2 normalk = normalj * radius + Vector2(min_radius + radius, 0);
				pts.push_back(Vector3(normali.x * normalk.x, normalk.y, normali.y * normalk.x));
				if (i > 0 && j > 0) {
					ix.insert(ix.end(), { thisrow + j - 1, prevrow + j, prevrow + j - 1, thisrow + j - 1, thisrow + j, prevrow + j });
				}
			}
		}
	} else {
		return out;
	}
	soupe(pts, ix, prim->get_flip_faces(), out);
	return out;
}
