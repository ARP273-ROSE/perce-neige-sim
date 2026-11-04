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

	// Grille nj × ni tirée d'une grille plus fine ou plus grossière sj × si (bilinéaire) : `rapport` =
	// pas de la sortie / pas de la source. Voie moyenne : 2,5 m à partir du niveau à 2 m du pack.
	PackedFloat32Array reechantillonner(const PackedFloat32Array &src, int sj, int si, int nj, int ni, double rapport) const;

	// Quart d'anneau, depuis le nœud (j0, i0), d mailles de côté : [sommets, indices], sans les mailles
	// du carré [t0, t1[ si t1 > t0.
	Array quart_anneau(int j0, int i0, int d, int t0, int t1) const;

	// Texture de détail de la neige, calculée au chargement (rien dans le dépôt) : RGBA8 raccordable, côté
	// `taille`. R, G : pente d'un bruit à plusieurs échelles ; B : grain fin ; A : le bruit lui-même.
	PackedByteArray texture_detail(int taille) const;

	// Mémoire vidéo dédiée de la plus grosse carte (Go), 0 si elle n'est pas connue.
	double memoire_video() const;

	// Altitude sur les triangles de la grille (mêmes diagonales que le maillage).
	static float hauteur_tri(const float *g, int64_t nj, int64_t ni, double fx, double fz);

	// Niveaux 1 à niveaux − 1 du sol, chacun filtré depuis le précédent ([1 2 1] sur chaque axe) : les
	// anneaux lointains n'y crénellent plus les barres rocheuses.
	Array pyramide(const PackedFloat32Array &hn, int nj, int ni, int niveaux) const;

	// Anneaux de l'affichage : pour chaque niveau n, (m + 1)² couples RG, un nœud sur 2^n, autour de
	// (cj, ci) en nœuds. R : l'altitude du niveau ; G : celle du niveau suivant au même point, que
	// l'anneau rejoint à son bord (dernier niveau : le relief à 25 m, sur lequel il se pose).
	// `pyr` : résultat de pyramide. Hors de la grille : le nœud du bord.
	Array anneaux(const PackedFloat32Array &hn, const Array &pyr, int nj, int ni, const PackedFloat32Array &h, int nx, int nz, int k,
			int cj, int ci, int m, int niveaux) const;

	// Triangles du sol au mètre sur n × n mailles depuis le nœud (j0, i0) (mêmes diagonales que
	// l'affichage), sans les rectangles `rects` [x0, z0, x1, z1, …] : les pièces fines des gares.
	PackedVector3Array facettes(const PackedFloat32Array &hn, int nj, int ni, int j0, int i0, int n,
			double x0, double z0, double px, double pz, const PackedFloat32Array &rects) const;

	// Normales d'une couche du tableau de textures : `taille` texels dont `marge` pris aux voisines,
	// le texel (marge, marge) sur le nœud (ti, tj). BC5 avec tous ses niveaux, prêt pour Image.
	PackedByteArray normales_couche(const PackedFloat32Array &hn, int nj, int ni, int ti, int tj, int taille, int marge,
			double px, double pz) const;

	// Couches de l'orthophoto (cuisson_ortho_hd.gd), en parallèle : [format d'Image, texels, données…].
	// `sauter_niveaux` : niveaux de détail écartés (voie moyenne : 1, quatre fois moins de mémoire vidéo).
	// Vide si le fichier est illisible.
	Array couches(const String &chemin, int sauter_niveaux) const;

	// Forêt (arbres.pnhd, voir FORMAT_ARBRES dans tools_relief_hd.py) posée sur la grille : par case
	// [cx, cz, nombre, tampon MultiMesh 3D + couleur, 16 flottants par arbre]. Arbres écartés sous les
	// capsules et rectangles des ouvrages ; jeunes arbres ajoutés autour des grands (la détection garde
	// un sommet par fenêtre de 5 m, elle sous-compte les forêts serrées).
	Array foret(const String &chemin, const PackedFloat32Array &hn, int nj, int ni, double x0, double z0, double px, double pz,
			const PackedFloat32Array &capsules, const PackedFloat32Array &rects) const;

	// Toutes les couches d'un coup, en parallèle : `tuiles` nœuds par couche.
	Array normales(const PackedFloat32Array &hn, int nj, int ni, int tuile, int taille, int marge, double px, double pz) const;
};

} // namespace godot
