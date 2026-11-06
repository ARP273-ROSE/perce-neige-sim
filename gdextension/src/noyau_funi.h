// Calculs du funiculaire faits à chaque image, passés en C++ (réécriture du cœur,
// 06/11/2026). Chaque méthode remplace une boucle GDScript précise, avec les mêmes
// opérations du moteur ; le GDScript reste le chemin de secours quand le module manque.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class NoyauFuni : public RefCounted {
	GDCLASS(NoyauFuni, RefCounted)

protected:
	static void _bind_methods();

public:
	// Tube du tronçon libre du câble au culot (TrackBuilder._tube_amorce) : un anneau de
	// `ns` + 1 sommets autour de chaque point `pts[i]`, dans le repère de la voie
	// (`voie_x[i]`, `voie_y[i]`) rendu orthogonal à la tangente ; UV = (j / ns, `uv_v[i]`).
	// Renvoie les tableaux d'une surface de triangles non indexés (VERTEX, NORMAL,
	// TEX_UV), faces dans le même sens que le GDScript ; tableau vide si moins de 2 points.
	Array tube_cable(const PackedVector3Array &pts, const PackedVector3Array &voie_x,
			const PackedVector3Array &voie_y, const PackedFloat32Array &uv_v, double rayon, int ns) const;
};

} // namespace godot
