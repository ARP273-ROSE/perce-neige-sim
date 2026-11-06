// Noyau de calcul des remontées (C++, GDExtension) — demande d'un utilisateur du
// 26/10/2026 : « va falloir te pencher sur le C++, on n'a pas les perfs pour
// augmenter le décor ». Il reprend, pour toute une ligne et en un seul appel
// par image, ce que LigneRemontee._process faisait véhicule par véhicule en
// GDScript : avance sur la boucle (profil des lanceurs), charges ponctuelles et
// flèche du câble par portée (avec l'onde des arrêts), pose de chaque véhicule
// (position, cap, inclinaison de la pince), balancement en pendule, corps de
// collision, et pièces animées en gare (pince, garde-corps, bulle, portes) —
// les appels de méthode n'ont lieu que quand la valeur change.
//
// Mêmes formules que le GDScript (ligne_remontee.gd, vehicule_remontee.gd) ;
// les cas particuliers restent en GDScript : tronçons jumelés (Bollin–Fresse),
// 3S, téléphériques, téléskis à magasin.
#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <vector>

namespace godot {

class NoyauRemontee : public RefCounted {
	GDCLASS(NoyauRemontee, RefCounted)

	// --- géométrie de la ligne (repère de la ligne) ---------------------------
	PackedVector3Array boucle;
	PackedFloat32Array cumul;
	double longueur = 0.0;
	// zones de gare : [début, fin] en abscisse, code 0 aval / 1 amont ; et, par
	// zone, les repères du garde-corps (x_haut, x_bas)
	std::vector<double> z_debut, z_fin, z_haut, z_bas;
	std::vector<int> z_code;
	// appuis du câble (nez des gares, têtes de pylônes), abscisse horizontale d
	std::vector<double> appuis;

	// --- constantes ------------------------------------------------------------
	double vitesse = 5.0;
	double v_emb = 1.0;
	double l_frein = 18.0;
	double l_ouverture = 2.5;
	bool fixe = false;
	bool sens_droite = true;
	double signe_montee = 1.0;            // signe de _x_brin(true)
	bool cabine = false;
	double masse = 650.0;
	double charge_montee = 0.0;           // passagers sur le brin montant (kg)
	double longueur_pendule = 2.6;
	Vector3 pivot;                        // pivot du balancier (corps de collision)
	double poids[2] = {0.0, 0.0};         // poids d'un véhicule / tension (montée, descente)
	double w_veh[2] = {0.0, 0.0};         // charge répartie / tension

	// --- nœuds -----------------------------------------------------------------
	std::vector<Node3D *> vehicules, pinces, susps, corps;

	// --- état par véhicule -----------------------------------------------------
	std::vector<double> s_veh;
	// temps de parcours par véhicule (table s tous les 0,05 s à régime 1)
	std::vector<float> tab_s;
	std::vector<double> t_veh;
	std::vector<double> s_repere;
	std::vector<double> phi, psi, dphi, dpsi;
	// équilibre du balancement latéral : passagers tirés au sort, joueur à bord, guide d'entrée de gare
	std::vector<double> psi0_tire;
	int i_joueur = -1;
	double psi0_joueur = 0.0;
	double guide_l = 0.0, guide_gorge = 0.01, guide_ouvert = 0.22, guide_bras = 0.49;
	double limite_guide(double s) const;
	std::vector<Vector3> p_prec, v_prec, a_f;
	std::vector<int> n_mes;
	std::vector<float> e_ouv, e_gc, e_porte;   // dernières valeurs envoyées (−1 : jamais)

	// --- charges ponctuelles (par brin, puis par portée) ------------------------
	std::vector<Vector2> charges[2];
	std::vector<std::vector<Vector2>> charges_portee[2];
	PackedFloat32Array paquets;           // pour le shader du câble : 2 × 32 × 4 + 2

	int tour = 0;
	std::vector<int> gare_derniere;
	std::vector<RID> mm_rid;
	std::vector<Transform3D> mm_rel;
	double mm_seuil = 0.0, mm_jusqua = 0.0;
	std::vector<Transform3D> pose_veh;   // dernière pose (repère de la ligne)
	std::vector<char> loin_veh;          // 1 : dessiné en MultiMesh
	std::vector<float> mm_buf;
	std::vector<double> z_xa;
	std::vector<int> passages_derniers;
	double d_onde_amp = 0.0, d_onde_t = 0.0, d_a_montee = 800.0;
	Object *ligne = nullptr;              // pour les collisions des portes des cabines

	struct Zone {
		int idx;   // −1 : en ligne
		double x;
		double l;
	};
	Zone zone(double s) const;
	double vitesse_en(double s) const;
	double t_de_s(double s) const;
	double s_de_t(double t) const;
	void point_cable(double s, Vector3 &p, Vector3 &d) const;
	int portee_de(double d) const;
	double fleche(double d, bool montee, double onde_amp, double onde_t, double a_montee) const;

protected:
	static void _bind_methods();

public:
	// Relief fin (relief_fin.gd) : altitudes des nœuds de la grille fine, fusion du relief à
	// 25 m et de l'écart lu. Renvoie [altitudes, mailles fines, relief à 25 m recalé].
	Array fusion_relief(const PackedFloat32Array &h, const PackedFloat32Array &h0, const PackedByteArray &ecart,
			int nx, int nz, int k, const PackedFloat32Array &rects, double x0, double z0, double dx, double dz) const;
	void set_boucle(const PackedVector3Array &p_boucle, const PackedFloat32Array &p_cumul, double p_longueur);
	void set_zones(const PackedFloat32Array &debut, const PackedFloat32Array &fin, const PackedInt32Array &code,
			const PackedFloat32Array &x_haut, const PackedFloat32Array &x_bas);
	void set_appuis(const PackedFloat32Array &p_appuis);
	void set_constantes(const Dictionary &c);
	void set_temps(const PackedFloat32Array &p_tab_s);
	void set_vehicules(const Array &p_vehicules, const Array &p_pinces, const Array &p_susps, const Array &p_corps,
			const PackedFloat64Array &s, const PackedFloat32Array &p_phi, const PackedFloat32Array &p_psi);
	void set_charges(const PackedFloat32Array &p_tires);
	void set_charge_joueur(int i, double p_psi0) {
		i_joueur = i;
		psi0_joueur = p_psi0;
	}
	void set_vitesse(double v) { vitesse = v; }
	void set_ligne(Object *p_ligne) { ligne = p_ligne; }

	// Une image : avance (dt_avance), charges, poses ; renvoie les abscisses
	// (à recopier dans _vehicules). `vue` : point de vue dans le repère de la
	// ligne ; `vue_active` faux à bord (tout à pleine cadence).
	PackedFloat64Array etape(double dt, double regime, const Vector3 &vue, bool vue_active, bool corps_actifs,
			double onde_amp, double onde_t, double a_montee, bool charges_actives);
	PackedFloat32Array get_paquets() const { return paquets; }
	// flèche locale (charges et onde de la dernière étape) : calage des galets
	double fleche_en(double d, bool montee) const { return fleche(d, montee, d_onde_amp, d_onde_t, d_a_montee); }

	// Portillons : abscisse (dans la zone) où un véhicule finit son demi-tour,
	// par zone ; passages() : [zone, véhicule, …] franchis à la dernière étape
	void set_portillons(const PackedFloat32Array &xa);
	PackedInt32Array passages() const;

	// Véhicules en gare à la dernière étape (tronçons jumelés : le GDScript les
	// repose, contour et traversée)
	PackedInt32Array en_gare() const;

	// Véhicules lointains dessinés en MultiMesh (un appel de dessin par maillage
	// et par ligne) : un MultiMesh par maillage du modèle, sa transformation
	// relative au véhicule ; au-delà de `seuil` du point de vue, le nœud du
	// véhicule est caché et l'instance prend sa pose.
	void set_lointains(const Array &multimeshes, const Array &relatives, double seuil, double jusqua);

	// Galets : pour chaque véhicule sur une voie de ligne à moins de 6 m d'un
	// pylône (abscisses pylones_d), [k, montée (1/0), u = d_pylône − d, …]
	PackedFloat32Array touches(const PackedFloat32Array &pylones_d, double voie) const;

	// Prototype : positions et directions aux abscisses s : [p0, d0, p1, d1, …]
	PackedVector3Array points(const PackedFloat32Array &s) const;

	// Calage des paires de galets des pylônes sur le câble affiché (port de PyloneRemontee._pose_paire) :
	// par pylône i, son abscisse d, la hauteur y_t de l'axe de sa tête, la pente de chaque tête, la hauteur du
	// câble sans flèche échantillonnée de d0 au pas `pas` pour chaque brin, et ses paires [zp, sgn, demi].
	void set_calage(int64_t i, double d, double y_t, double pente_m, double pente_d, double dist, double d0, double pas,
			const PackedFloat32Array &y_m, const PackedFloat32Array &y_d, const PackedVector3Array &paires_m,
			const PackedVector3Array &paires_d);
	bool a_calage(int64_t i) const { return i >= 0 && i < (int64_t)calages.size() && calages[i].pret; }
	// [y, z, pente] de chaque paire, brin montant puis descendant, flèche du moment (onde comprise)
	PackedFloat32Array caler(int64_t i) const;

private:
	struct Calage {
		bool pret = false;
		double d = 0.0, y_t = 0.0, pente[2] = {0.0, 0.0}, dist = 0.0, d0 = 0.0, pas = 0.05;
		std::vector<float> y[2];
		std::vector<Vector3> paires[2];
	};
	std::vector<Calage> calages;
	double cable_calage(const Calage &c, int b, double z) const;
};

} // namespace godot
