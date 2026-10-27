// Fusion des maillages (MeshMerge, mesh_merge.gd) : l'assemblage d'un groupe —
// positions, normales, tangentes, couleurs, UV, indices — passé en C++, en un
// seul appel par groupe (appel par surface : chaque fois le tableau accumulé
// était recopié, copie à l'écriture des tableaux de Godot). En GDScript, elle
// faisait l'essentiel des 10 à 40 ms de chaque pylône construit (banc de
// fluidité du 27/10/2026). Mêmes opérations du moteur (Transform3D::xform,
// Basis::xform, Vector3::normalized) que le GDScript qu'elle remplace.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/array.hpp>

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
};

} // namespace godot
