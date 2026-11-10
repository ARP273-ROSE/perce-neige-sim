// Maillage de texte figé (RemonteeKit.maillage_texte) calculé ici, sur le processeur : mêmes opérations que
// TextMesh._create_mesh_array du moteur 4.6 (mise en forme par le serveur de texte, contours des glyphes, courbes
// en segments, découpe par polypartition), pour une profondeur nulle. Le TextMesh, lui, envoie son maillage au
// serveur de rendu puis le relit (get_mesh_arrays) : la relecture attend la carte graphique, et le fil principal
// restait bloqué ~32 ms (deux images à 60 Hz) à chaque nouveau texte construit sur le fil de travail
// (relevé du PC du 10/11/2026 : une image de 48 ms sur quatre ou cinq près d'une ligne en construction).
#pragma once

#include <godot_cpp/classes/font.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class OutilsTexte : public RefCounted {
	GDCLASS(OutilsTexte, RefCounted)

protected:
	static void _bind_methods();

public:
	// Tableaux de surface (sommets, normales, tangentes, UV, indices), comme TextMesh avec depth = 0, width = 500,
	// alignement vertical centré, sans retour à la ligne automatique. Alignement horizontal : 0 gauche,
	// 1 centre, 2 droite (3, remplissage : non pris en charge, rend un tableau vide).
	Array maillage(const Ref<Font> &font, const String &texte, int64_t taille, double pixel, double pas_courbe,
			int64_t aligne, const String &langue) const;
};

} // namespace godot
