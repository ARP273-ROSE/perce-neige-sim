// Fusion des maillages (MeshMerge, mesh_merge.gd) : l'assemblage d'un groupe —
// positions, normales, tangentes, couleurs, UV, indices — passé en C++, en un
// seul appel par groupe (appel par surface : chaque fois le tableau accumulé
// était recopié, copie à l'écriture des tableaux de Godot). En GDScript, elle
// faisait l'essentiel des 10 à 40 ms de chaque pylône construit (banc de
// fluidité du 27/10/2026). Mêmes opérations du moteur (Transform3D::xform,
// Basis::xform, Vector3::normalized) que le GDScript qu'elle remplace.
#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/primitive_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class OutilsMaillage : public RefCounted {
	GDCLASS(OutilsMaillage, RefCounted)

protected:
	static void _bind_methods();

public:
	// Une surface fusionnée (tableaux de Mesh) à partir de `surfaces` (tableaux
	// de chaque source, même format) et de leurs `transformations` : positions
	// par xf, normales par l'inverse transposée (normalisées), tangentes par la
	// base (normalisées), couleurs et UV recopiées, indices décalés.
	Array fusionner(const Array &surfaces, const Array &transformations) const;

	// Tube le long de `pts` (RemonteeKit.tube_tableaux_plage) : tranches des segments [i0, i1[, triangles non
	// indexés, normales radiales, UV (tour, 2 × abscisse). Mêmes opérations, dans le même ordre, que le GDScript
	// (scalaires en double, vecteurs en float). Rend [sommets, normales, uv, x du repère pour la plage suivante,
	// abscisse à la fin].
	Array tube_plage(const PackedVector3Array &pts, double r, int64_t seg, int64_t i0, int64_t i1,
			const Vector3 &prec_x, double absc) const;

	// MeshMerge en C++ (outils_fusion.cpp) — mêmes résultats que le GDScript :
	// _a_fusionner : [MeshInstance3D, transformation dans le repère de root, identifiant] des pièces à fusionner.
	Array parcourir(Node3D *root, const Array &keep) const;
	// _collect sur elements[debut..] jusqu'à épuisement de budget_us (0 : sans limite), au moins une pièce ;
	// rend l'indice suivant. cpu, verrou, repli : MeshMerge._cpu, MeshMerge.verrou, MeshMerge.tableaux.
	int64_t collecter(const Array &elements, int64_t debut, int64_t budget_us, Dictionary groups,
			const Dictionary &cpu, const Variant &verrou, const Callable &repli) const;
	// _retirer_sources : pièces entièrement fusionnées retirées (libérées hors de la scène).
	void retirer(const Dictionary &done) const;
	// Triangles (soupe, comme MeshMerge.faces) d'un cylindre, d'une sphère ou d'un tore, calculés comme le moteur ;
	// vide pour une autre primitive.
	PackedVector3Array faces_primitive(const Ref<PrimitiveMesh> &prim) const;
};

} // namespace godot
