// Relief haute définition du PC : lecture du pack (relief.pnhd, voir FORMAT_RELIEF dans
// tools_relief_hd.py), sol à 1 m raccordé aux ouvrages, anneaux d'altitudes de l'affichage,
// normales compressées. Tout est préparé sur des fils de travail, sans toucher à l'arbre de scène.
// Le module n'existe pas sur la PWA, et ce chemin ne sert que si le pack est présent.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class ReliefHD : public RefCounted {
	GDCLASS(ReliefHD, RefCounted)

protected:
	static void _bind_methods();

public:
	// Grille du niveau `niveau` (pas = 2^niveau mailles) : altitudes de tout le pack, en parallèle.
	// Vide si le fichier est illisible ou si sa grille n'est pas nj × ni au niveau 0.
	PackedFloat32Array decoder(const String &chemin, int niveau, int nj, int ni) const;

	// Sol à k_h mailles par maille à 25 m, à partir de la grille de référence (k_r par maille,
	// le sol réglé du jeu) : la référence là où passent les ouvrages, le relevé `leve` (même
	// grille que le résultat) ailleurs, raccordés. `capsules` : [ax, az, bx, bz, r0, r1, …] ;
	// `rects` : [x0, z0, x1, z1, …], élargis d'un raccord `r1_rect`. Mailles à 25 m retouchées :
	// écart de h à h0. Renvoie [altitudes, mailles fines, relief à 25 m recalé].
	Array raccorder(const PackedFloat32Array &leve, const PackedFloat32Array &ref, const PackedByteArray &fine_ref,
			const PackedFloat32Array &h, const PackedFloat32Array &h0, int nx, int nz, int k_h, int k_r,
			const PackedFloat32Array &capsules, const PackedFloat32Array &rects, double r1_rect,
			double x0, double z0, double px, double pz) const;

	// Altitude sur les triangles de la grille (mêmes diagonales que le maillage).
	static float hauteur_tri(const float *g, int64_t nj, int64_t ni, double fx, double fz);

	// Anneaux de l'affichage : pour chaque niveau n, (m + 1)² altitudes RF, un nœud sur 2^n, autour
	// de (cj, ci) en nœuds. Le dernier niveau est RGF : G = le relief à 25 m, sur lequel il se pose
	// à son bord. Hors de la grille : le nœud du bord.
	Array anneaux(const PackedFloat32Array &hn, int nj, int ni, const PackedFloat32Array &h, int nx, int nz, int k,
			int cj, int ci, int m, int niveaux) const;

	// Normales d'une couche du tableau de textures : `taille` texels dont `marge` pris aux voisines,
	// le texel (marge, marge) sur le nœud (ti, tj). BC5 avec tous ses niveaux, prêt pour Image.
	PackedByteArray normales_couche(const PackedFloat32Array &hn, int nj, int ni, int ti, int tj, int taille, int marge,
			double px, double pz) const;

	// Toutes les couches d'un coup, en parallèle : `tuiles` nœuds par couche.
	Array normales(const PackedFloat32Array &hn, int nj, int ni, int tuile, int taille, int marge, double px, double pz) const;
};

} // namespace godot
