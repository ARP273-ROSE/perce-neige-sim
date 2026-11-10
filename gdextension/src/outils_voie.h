// Voie et tunnel (TrackBuilder, track_builder.gd) : émission des sommets des bandes rectangulaires extrudées le long
// de la voie (patin, âme, champignon des rails), en un appel par tronçon. En GDScript, l'émission sommet par sommet
// dans un SurfaceTool faisait l'essentiel des 120 ms d'un bloc des rails du Funival (relevé du PC, 08/11/2026).
// Mêmes opérations du moteur (Vector3 en réels simples, décalages en doubles comme les flottants de GDScript) que le
// repli GDScript (ExtrusionVoie.bandes_gd) : les deux donnent les mêmes tableaux, octet pour octet
// (bench_empreinte_pn.gd, avec et sans le module).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class OutilsVoie : public RefCounted {
	GDCLASS(OutilsVoie, RefCounted)

protected:
	static void _bind_methods();

public:
	// Pour chaque pas entre deux sections consécutives (origine, droite, haut, centre latéral cx, abscisse s), pour
	// chaque bande [y_bas, y_haut, demi-largeur basse, demi-largeur haute] de `bandes` : faces gauche, droite et
	// dessus, deux triangles chacune. Rend [sommets (PackedVector3Array), UV (PackedVector2Array)], dans l'ordre
	// d'émission de TrackBuilder._emit_rail_step_xv.
	Array extruder_bandes(const PackedVector3Array &origines, const PackedVector3Array &droites,
			const PackedVector3Array &hauts, const PackedFloat64Array &cx, const PackedFloat64Array &s,
			const PackedFloat64Array &bandes) const;

	// Tube d'un tronçon de brin du câble (TrackBuilder._build_cable_segment) à partir de ses anneaux (centre, droite,
	// haut, abscisse s, descente détendue d) : ns + 1 sommets par anneau, normales vers l'axe, UV (secteur, 2 s), UV2
	// (descente, descente / dmax), COLOR (droite de la voie), indices. Mêmes opérations que le repli GDScript
	// (cos et sin du moteur ; scalaires en double, vecteurs en float). Rend [sommets, normales, uv, uv2, couleurs,
	// indices].
	Array tube_brin(const PackedVector3Array &centres, const PackedVector3Array &droites, const PackedVector3Array &hauts,
			const PackedFloat64Array &s, const PackedFloat64Array &d, int64_t ns, double rayon, double dmax) const;
};

} // namespace godot
