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
#include <godot_cpp/classes/point_mesh.hpp>
#include <godot_cpp/classes/primitive_mesh.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/weak_ref.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

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
