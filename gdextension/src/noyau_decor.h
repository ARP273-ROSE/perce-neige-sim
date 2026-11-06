// Collisions du décor (CollisionsJeu._terrain) : pièces fines des gares, passées en C++
// (06/11/2026). Le GDScript faisait une tâche de 12 à 28 ms d'un seul tenant (une image
// figée à l'entrée du skieur). Mêmes calculs, même ordre ; repli GDScript sans le module.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

#include <vector>

namespace godot {

class NoyauDecor : public RefCounted {
	GDCLASS(NoyauDecor, RefCounted)

	struct Piece {
		Rect2 r;
		int nx = 0, nz = 0;
		PackedFloat32Array hs;
		PackedByteArray masque;
		int mw = 0, mh = 0;
	};
	std::vector<Piece> pieces;

	// ReliefBuilder.terrain_piece : hauteur (NaN hors des pièces) et « dans un bâtiment »
	double terrain_piece(double x, double z, bool &trou) const;

protected:
	static void _bind_methods();

public:
	// [[rect, nx, nz, hauteurs, masque L8 (octets), largeur, hauteur], …] (ReliefBuilder._pieces)
	void set_pieces(const Array &p_pieces);
	// Sommets de la grille de pas `pas` sur rp, (nx + 1) × (nz + 1) : [hauteurs (NaN hors des
	// pièces, à compléter par ReliefBuilder._hauteur_tri), trous (0/1), indices des NaN].
	Array piece_grille(const Rect2 &rp, double pas, int nx, int nz) const;
	// Complète les NaN de piece_grille par la hauteur de la grille du bloc (ReliefBuilder._tri_sur :
	// `grille` nxg × nzg, origine x_ouest / z_nord, pas dx / dz, sous-échantillonnée de `pasg`),
	// sauf là où le relief fin est le sol (`fine` par maille, ncx × ncz, vide sans relief fin) :
	// [hauteurs, indices restés NaN (à faire par ReliefFin.hauteur)].
	Array completer_tri(const PackedFloat32Array &h, const PackedInt32Array &nans, const Rect2 &rp, double pas, int nx,
			const PackedFloat32Array &grille, int nxg, int nzg, double x_ouest, double z_nord, double dx, double dz,
			int pasg, const PackedByteArray &fine, int ncx, int ncz, double lx, double lz) const;
	// Triangles des mailles (a, b, c) puis (b, d, c), sauf celles dont le centre est dans un bâtiment.
	PackedVector3Array piece_faces(const Rect2 &rp, double pas, int nx, int nz,
			const PackedFloat32Array &h, const PackedByteArray &trou) const;
};

} // namespace godot
