// Calculs du funiculaire faits à chaque image, passés en C++ (réécriture du cœur,
// 06/11/2026). Chaque méthode remplace une boucle GDScript précise, avec les mêmes
// opérations du moteur ; le GDScript reste le chemin de secours quand le module manque.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

class NoyauFuni : public RefCounted {
	GDCLASS(NoyauFuni, RefCounted)

protected:
	static void _bind_methods();

	PackedVector3Array noeuds;
	double pas = 1.0;
	double longueur = 0.0;
	double croise_debut = 0.0, croise_fin = 0.0, croise_max = 0.0;

	Vector3 position_rame(double s, double cote) const;
	static Transform3D repere_caisse(const Vector3 &pos, const Vector3 &tangente);

public:
	// B-spline cubique uniforme du tracé (TunnelBuilder._build_smooth_path) : nœuds tous les
	// `pas` mètres, un nœud prolongé de chaque côté ; `longueur` = longueur de la ligne.
	void set_spline(const PackedVector3Array &p_noeuds, double p_pas, double p_longueur);
	// TunnelBuilder.transform_at : position et repère (droite, haut, −tangente) à l'abscisse s.
	Transform3D transform_at(double s) const;
	// Évitement (TunnelBuilder.passing_loop_offset) : début, fin, décalage latéral maximal.
	void set_croisement(double debut, double fin, double decal_max);
	double passing_loop_offset(double s, double cote) const;
	// Pose d'une rame (Cabin._process_corps) : [repère de la rame, puis celui de chaque
	// voiture, posée sur ses deux bogies à ±`demi_bogie` de son centre].
	Array poses_rame(double s_pos, double cote, int nb_voitures, double long_voiture, double demi_bogie) const;
	// Les mêmes à plusieurs abscisses d'un coup (un seul appel depuis le GDScript).
	Array transforms_at(const PackedFloat32Array &s) const;

	// Tube du tronçon libre du câble au culot (TrackBuilder._tube_amorce) : un anneau de
	// `ns` + 1 sommets autour de chaque point `pts[i]`, dans le repère de la voie
	// (`voie_x[i]`, `voie_y[i]`) rendu orthogonal à la tangente ; UV = (j / ns, `uv_v[i]`).
	// Renvoie les tableaux d'une surface de triangles non indexés (VERTEX, NORMAL,
	// TEX_UV), faces dans le même sens que le GDScript ; tableau vide si moins de 2 points.
	Array tube_cable(const PackedVector3Array &pts, const PackedVector3Array &voie_x,
			const PackedVector3Array &voie_y, const PackedFloat32Array &uv_v, double rayon, int ns) const;
};

} // namespace godot
