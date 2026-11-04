#include "relief_hd.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <functional>
#include <thread>
#include <vector>

using namespace godot;

namespace {

// n tâches sur tous les cœurs (chargement : jamais pendant une image)
void en_parallele(int64_t n, const std::function<void(int64_t)> &f) {
#ifdef __EMSCRIPTEN__
	// (pas de fils sur le web ; ce chemin n'y sert pas)
	for (int64_t k = 0; k < n; k++) {
		f(k);
	}
#else
	const int nb = std::max(1, int(std::thread::hardware_concurrency()));
	std::atomic<int64_t> suivant(0);
	std::vector<std::thread> fils;
	auto travail = [&]() {
		for (;;) {
			const int64_t k = suivant.fetch_add(1);
			if (k >= n) {
				return;
			}
			f(k);
		}
	};
	for (int i = 1; i < nb; i++) {
		fils.emplace_back(travail);
	}
	travail();
	for (std::thread &t : fils) {
		t.join();
	}
#endif
}

#pragma pack(push, 1)
struct EntreeTuile {
	uint8_t niveau;
	uint8_t reserve8;
	uint16_t reserve16;
	uint32_t ti, tj;
	uint16_t largeur, hauteur;
	float base, pas;
	uint64_t position;
	uint32_t taille;
};
#pragma pack(pop)
static_assert(sizeof(EntreeTuile) == 36, "index du pack");

const float SEUIL_ABERRATION = 30.0f;     // m d'écart à la médiane de 9 × 9 nœuds

inline float lisse(float a, float b, float x) {
	if (b <= a) {
		return x < a ? 0.0f : 1.0f;
	}
	const float t = std::min(std::max((x - a) / (b - a), 0.0f), 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

// Un canal d'un bloc BC4 (16 valeurs) : bornes min et max, six valeurs interpolées.
inline void bloc_bc4(const uint8_t *v, uint8_t *o) {
	int mi = 255;
	int ma = 0;
	for (int i = 0; i < 16; i++) {
		mi = std::min(mi, int(v[i]));
		ma = std::max(ma, int(v[i]));
	}
	if (ma == mi) {
		o[0] = uint8_t(ma);
		o[1] = uint8_t(mi);
		std::memset(o + 2, 0, 6);
		return;
	}
	o[0] = uint8_t(ma);
	o[1] = uint8_t(mi);
	uint64_t bits = 0;
	const int e = ma - mi;
	for (int i = 0; i < 16; i++) {
		// 0..7 de mi à ma, arrondi ; code BC4 : 0 = ma, 1 = mi, 2..7 = de ma vers mi
		const int t = (2 * 7 * (int(v[i]) - mi) + e) / (2 * e);
		const int code = t == 7 ? 0 : (t == 0 ? 1 : 8 - t);
		bits |= uint64_t(code) << (3 * i);
	}
	std::memcpy(o + 2, &bits, 6);
}

// Taille des données d'une image BC5 carrée avec tous ses niveaux, telle que l'attend Image.
inline int64_t taille_bc5(int taille) {
	int64_t t = 0;
	int w = taille;
	for (;;) {
		const int b = std::max((w + 3) / 4, 1);
		t += int64_t(b) * b * 16;
		if (w == 1) {
			return t;
		}
		w = std::max(w / 2, 1);
	}
}

} // namespace

void ReliefHD::_bind_methods() {
	ClassDB::bind_method(D_METHOD("decoder", "chemin", "niveau", "nj", "ni"), &ReliefHD::decoder);
	ClassDB::bind_method(D_METHOD("raccorder", "leve", "ref", "fine_ref", "h", "h0", "nx", "nz", "k_h", "k_r", "capsules", "rects", "r1_rect", "x0", "z0", "px", "pz"), &ReliefHD::raccorder);
	ClassDB::bind_method(D_METHOD("anneaux", "hn", "nj", "ni", "h", "nx", "nz", "k", "cj", "ci", "m", "niveaux"), &ReliefHD::anneaux);
	ClassDB::bind_method(D_METHOD("normales_couche", "hn", "nj", "ni", "ti", "tj", "taille", "marge", "px", "pz"), &ReliefHD::normales_couche);
	ClassDB::bind_method(D_METHOD("couches", "chemin"), &ReliefHD::couches);
	ClassDB::bind_method(D_METHOD("normales", "hn", "nj", "ni", "tuile", "taille", "marge", "px", "pz"), &ReliefHD::normales);
}

PackedFloat32Array ReliefHD::decoder(const String &chemin, int niveau, int nj, int ni) const {
	PackedFloat32Array sortie;
	Ref<FileAccess> f = FileAccess::open(chemin, FileAccess::READ);
	if (f.is_null()) {
		return sortie;
	}
	const PackedByteArray b_tete = f->get_buffer(48);
	if (b_tete.size() != 48 || std::memcmp(b_tete.ptr(), "PNRH", 4) != 0) {
		return sortie;
	}
	const char *tete = reinterpret_cast<const char *>(b_tete.ptr());
	uint32_t pack_nj, pack_ni, n;
	std::memcpy(&pack_nj, tete + 32, 4);
	std::memcpy(&pack_ni, tete + 36, 4);
	std::memcpy(&n, tete + 44, 4);
	const PackedByteArray b_index = f->get_buffer(int64_t(n) * 36);
	if (b_index.size() != int64_t(n) * 36) {
		return sortie;
	}
	std::vector<EntreeTuile> index(n);
	std::memcpy(index.data(), b_index.ptr(), size_t(n) * 36);
	const uint64_t corps = uint64_t(48) + uint64_t(n) * 36;
	const int pas = 1 << niveau;
	if (int64_t(pack_nj - 1) / pas + 1 != nj || int64_t(pack_ni - 1) / pas + 1 != ni) {
		return sortie;
	}
	std::vector<EntreeTuile> tuiles;
	for (const EntreeTuile &e : index) {
		if (e.niveau == niveau) {
			tuiles.push_back(e);
		}
	}
	sortie.resize(int64_t(nj) * ni);
	float *ps = sortie.ptrw();
	std::atomic<int> erreurs(0);
	en_parallele(int64_t(tuiles.size()), [&](int64_t k) {
		const EntreeTuile &e = tuiles[size_t(k)];
		Ref<FileAccess> fk = FileAccess::open(chemin, FileAccess::READ);
		if (fk.is_null()) {
			erreurs++;
			return;
		}
		fk->seek(corps + e.position);
		const PackedByteArray brut = fk->get_buffer(e.taille);
		if (brut.size() != int64_t(e.taille)) {
			erreurs++;
			return;
		}
		const int w = e.largeur;
		const int h = e.hauteur;
		const PackedByteArray clair = brut.decompress(int64_t(w) * h * 2, FileAccess::COMPRESSION_ZSTD);
		if (clair.size() != int64_t(w) * h * 2) {
			erreurs++;
			return;
		}
		const uint8_t *pc = clair.ptr();
		std::vector<uint16_t> q(size_t(w) * h);
		std::memcpy(q.data(), pc, size_t(w) * h * 2);
		for (int i = 0; i < h; i++) {
			uint16_t *l = q.data() + size_t(i) * w;
			if (i > 0) {
				l[0] = uint16_t(l[0] + l[int64_t(-w)]);
			}
			for (int j = 1; j < w; j++) {
				l[j] = uint16_t(l[j] + l[j - 1]);
			}
		}
		// bord partagé : la tuile de gauche et celle du dessus font foi (bases différentes, 2 cm au plus)
		const int ia = e.ti > 0 ? 1 : 0;
		const int ja = e.tj > 0 ? 1 : 0;
		for (int i = ia; i < h; i++) {
			const int64_t gi = int64_t(e.ti) + i;
			if (gi >= ni) {
				break;
			}
			float *out = ps + gi * nj + e.tj;
			const uint16_t *l = q.data() + size_t(i) * w;
			const int fin = std::min<int64_t>(w, int64_t(nj) - e.tj);
			for (int j = ja; j < fin; j++) {
				out[j] = e.base + float(l[j]) * e.pas;
			}
		}
	});
	if (erreurs.load() > 0) {
		UtilityFunctions::print("[ReliefHD] tuiles illisibles : ", erreurs.load());
		return PackedFloat32Array();
	}
	// Aberrations du relevé : quelques nœuds isolés, à des centaines de mètres de leurs voisins
	// (2636, 1409, 2634 m). Remplacés par la médiane autour d'eux, une barre rocheuse tient.
	std::vector<std::vector<int64_t>> a_corriger(static_cast<size_t>(ni));
	std::vector<std::vector<float>> valeurs(static_cast<size_t>(ni));
	en_parallele(ni, [&](int64_t i) {
		float fen[81];
		for (int64_t j = 1; j < nj; j++) {
			const float c = ps[i * nj + j];
			if (std::fabs(c - ps[i * nj + j - 1]) <= SEUIL_ABERRATION && (j + 1 >= nj || std::fabs(c - ps[i * nj + j + 1]) <= SEUIL_ABERRATION)) {
				continue;
			}
			int nb = 0;
			for (int64_t a = std::max<int64_t>(i - 4, 0); a <= std::min<int64_t>(i + 4, int64_t(ni) - 1); a++) {
				for (int64_t b = std::max<int64_t>(j - 4, 0); b <= std::min<int64_t>(j + 4, int64_t(nj) - 1); b++) {
					fen[nb++] = ps[a * nj + b];
				}
			}
			std::nth_element(fen, fen + nb / 2, fen + nb);
			if (std::fabs(c - fen[nb / 2]) > SEUIL_ABERRATION) {
				a_corriger[size_t(i)].push_back(j);
				valeurs[size_t(i)].push_back(fen[nb / 2]);
			}
		}
	});
	int64_t corriges = 0;
	for (int64_t i = 0; i < ni; i++) {
		for (size_t q = 0; q < a_corriger[size_t(i)].size(); q++) {
			ps[i * nj + a_corriger[size_t(i)][q]] = valeurs[size_t(i)][q];
			corriges++;
		}
	}
	UtilityFunctions::print(String::utf8("[ReliefHD] nœuds aberrants corrigés : "), corriges);
	return sortie;
}

float ReliefHD::hauteur_tri(const float *g, int64_t nj, int64_t ni, double fx, double fz) {
	const int64_t j = std::min<int64_t>(std::max<int64_t>(int64_t(fx), 0), nj - 2);
	const int64_t i = std::min<int64_t>(std::max<int64_t>(int64_t(fz), 0), ni - 2);
	const float u = float(fx - double(j));
	const float v = float(fz - double(i));
	const int64_t a = i * nj + j;
	if (u + v <= 1.0f) {
		return g[a] + (g[a + 1] - g[a]) * u + (g[a + nj] - g[a]) * v;
	}
	const float d = g[a + nj + 1];
	return d + (g[a + nj] - d) * (1.0f - u) + (g[a + 1] - d) * (1.0f - v);
}

Array ReliefHD::raccorder(const PackedFloat32Array &leve, const PackedFloat32Array &ref, const PackedByteArray &fine_ref,
		const PackedFloat32Array &h, const PackedFloat32Array &h0, int nx, int nz, int k_h, int k_r,
		const PackedFloat32Array &capsules, const PackedFloat32Array &rects, double r1_rect,
		double x0, double z0, double px, double pz) const {
	Array sortie;
	const int64_t nj = int64_t(nx - 1) * k_h + 1;
	const int64_t ni = int64_t(nz - 1) * k_h + 1;
	const int64_t njr = int64_t(nx - 1) * k_r + 1;
	const int64_t nir = int64_t(nz - 1) * k_r + 1;
	if (k_r < 1 || k_h % k_r != 0 || leve.size() != ni * nj || ref.size() != nir * njr
			|| h.size() != int64_t(nx) * nz || h0.size() != int64_t(nx) * nz) {
		return sortie;
	}
	// poids du relevé, sur une grille à 25 m ÷ k_r : 0 sous les ouvrages, 1 au large
	const double prx = px * double(k_h) / k_r;
	const double prz = pz * double(k_h) / k_r;
	std::vector<float> poids(size_t(nir * njr), 1.0f);
	float *pm = poids.data();
	for (int64_t q = 0; q + 5 < capsules.size(); q += 6) {
		const float ax = capsules[q];
		const float az = capsules[q + 1];
		const float bx = capsules[q + 2];
		const float bz = capsules[q + 3];
		const float r0 = capsules[q + 4];
		const float r1 = capsules[q + 5];
		const int64_t ja = std::max<int64_t>(int64_t(std::floor((std::min(ax, bx) - r1 - x0) / prx)), 0);
		const int64_t jb = std::min<int64_t>(int64_t(std::ceil((std::max(ax, bx) + r1 - x0) / prx)), njr - 1);
		const int64_t ia = std::max<int64_t>(int64_t(std::floor((std::min(az, bz) - r1 - z0) / prz)), 0);
		const int64_t ib = std::min<int64_t>(int64_t(std::ceil((std::max(az, bz) + r1 - z0) / prz)), nir - 1);
		const float ux = bx - ax;
		const float uz = bz - az;
		const float l2 = std::max(ux * ux + uz * uz, 1e-6f);
		for (int64_t i = ia; i <= ib; i++) {
			const float z = float(z0 + i * prz);
			for (int64_t j = ja; j <= jb; j++) {
				const float x = float(x0 + j * prx);
				const float t = std::min(std::max(((x - ax) * ux + (z - az) * uz) / l2, 0.0f), 1.0f);
				const float dx = x - (ax + ux * t);
				const float dz = z - (az + uz * t);
				const float w = lisse(r0, r1, std::sqrt(dx * dx + dz * dz));
				float &c = pm[size_t(i * njr + j)];
				c = std::min(c, w);
			}
		}
	}
	for (int64_t q = 0; q + 3 < rects.size(); q += 4) {
		const float rx0 = rects[q];
		const float rz0 = rects[q + 1];
		const float rx1 = rects[q + 2];
		const float rz1 = rects[q + 3];
		const float r1 = float(r1_rect);
		const int64_t ja = std::max<int64_t>(int64_t(std::floor((rx0 - r1 - x0) / prx)), 0);
		const int64_t jb = std::min<int64_t>(int64_t(std::ceil((rx1 + r1 - x0) / prx)), njr - 1);
		const int64_t ia = std::max<int64_t>(int64_t(std::floor((rz0 - r1 - z0) / prz)), 0);
		const int64_t ib = std::min<int64_t>(int64_t(std::ceil((rz1 + r1 - z0) / prz)), nir - 1);
		for (int64_t i = ia; i <= ib; i++) {
			const float z = float(z0 + i * prz);
			const float dz = std::max(std::max(rz0 - z, z - rz1), 0.0f);
			for (int64_t j = ja; j <= jb; j++) {
				const float x = float(x0 + j * prx);
				const float dx = std::max(std::max(rx0 - x, x - rx1), 0.0f);
				float &c = pm[size_t(i * njr + j)];
				c = std::min(c, lisse(0.0f, r1, std::sqrt(dx * dx + dz * dz)));
			}
		}
	}
	// mailles à 25 m retouchées (déblais) : sol de référence, raccord sur une maille
	const float *ph = h.ptr();
	const float *ph0 = h0.ptr();
	const int kr = k_r;
	en_parallele(nz - 1, [&](int64_t ci) {
		for (int cj = 0; cj < nx - 1; cj++) {
			bool tenu = false;
			for (int a = std::max<int>(int(ci) - 1, 0); a <= std::min<int>(int(ci) + 2, nz - 1) && !tenu; a++) {
				for (int b = std::max(cj - 1, 0); b <= std::min(cj + 2, nx - 1); b++) {
					if (std::fabs(ph[size_t(a) * nx + b] - ph0[size_t(a) * nx + b]) > 0.02f) {
						tenu = true;
						break;
					}
				}
			}
			if (tenu) {
				for (int a = int(ci) * kr; a <= (int(ci) + 1) * kr; a++) {
					std::fill(pm + size_t(a) * njr + size_t(cj) * kr, pm + size_t(a) * njr + size_t(cj + 1) * kr + 1, 0.0f);
				}
			}
		}
	});

	PackedFloat32Array hn;
	hn.resize(ni * nj);
	float *ps = hn.ptrw();
	PackedByteArray fine;
	fine.resize(int64_t(nx - 1) * (nz - 1));
	uint8_t *pf = fine.ptrw();
	std::memset(pf, 0, size_t(fine.size()));
	const float *pl = leve.ptr();
	const float *pr = ref.ptr();
	const uint8_t *pfr = fine_ref.ptr();
	const bool av_fine = fine_ref.size() == fine.size();
	const int rapport = k_h / k_r;
	en_parallele(ni, [&](int64_t i) {
		const double fz = double(i) / rapport;
		for (int64_t j = 0; j < nj; j++) {
			const double fx = double(j) / rapport;
			const int64_t jm = std::min<int64_t>(j / rapport, njr - 2);
			const int64_t im = std::min<int64_t>(i / rapport, nir - 2);
			const float u = float(fx - double(jm));
			const float v = float(fz - double(im));
			const size_t a = size_t(im * njr + jm);
			const float w = (pm[a] * (1.0f - u) + pm[a + 1] * u) * (1.0f - v)
					+ (pm[a + njr] * (1.0f - u) + pm[a + njr + 1] * u) * v;
			const float r = ReliefHD::hauteur_tri(pr, njr, nir, fx, fz);
			ps[i * nj + j] = r + (pl[i * nj + j] - r) * w;
			if (w > 0.0f) {
				const int ci = int(std::min<int64_t>(i / k_h, nz - 2));
				const int cj = int(std::min<int64_t>(j / k_h, nx - 2));
				pf[size_t(ci) * (nx - 1) + cj] = 1;
				if (i % k_h == 0 && ci > 0) {
					pf[size_t(ci - 1) * (nx - 1) + cj] = 1;
				}
				if (j % k_h == 0 && cj > 0) {
					pf[size_t(ci) * (nx - 1) + cj - 1] = 1;
				}
				if (i % k_h == 0 && j % k_h == 0 && ci > 0 && cj > 0) {
					pf[size_t(ci - 1) * (nx - 1) + cj - 1] = 1;
				}
			}
		}
	});
	if (av_fine) {
		for (int64_t q = 0; q < fine.size(); q++) {
			pf[q] = uint8_t(pf[q] | pfr[q]);
		}
	}
	PackedFloat32Array recale;
	recale.resize(int64_t(nx) * nz);
	float *prc = recale.ptrw();
	for (int i = 0; i < nz; i++) {
		for (int j = 0; j < nx; j++) {
			prc[size_t(i) * nx + j] = ps[int64_t(i) * k_h * nj + int64_t(j) * k_h];
		}
	}
	sortie.append(hn);
	sortie.append(fine);
	sortie.append(recale);
	return sortie;
}

Array ReliefHD::anneaux(const PackedFloat32Array &hn, int nj, int ni, const PackedFloat32Array &h, int nx, int nz, int k,
		int cj, int ci, int m, int niveaux) const {
	Array sortie;
	const float *ps = hn.ptr();
	const float *ph = h.ptr();
	const int w = m + 1;
	for (int n = 0; n < niveaux; n++) {
		const int s = 1 << n;
		const bool dernier = n == niveaux - 1;
		PackedByteArray o;
		o.resize(int64_t(w) * w * (dernier ? 8 : 4));
		float *po = reinterpret_cast<float *>(o.ptrw());
		const int j0 = cj - (m / 2) * s;
		const int i0 = ci - (m / 2) * s;
		for (int a = 0; a < w; a++) {
			const int gi = std::min(std::max(i0 + a * s, 0), ni - 1);
			const float *l = ps + int64_t(gi) * nj;
			if (!dernier) {
				float *out = po + size_t(a) * w;
				for (int b = 0; b < w; b++) {
					out[b] = l[std::min(std::max(j0 + b * s, 0), nj - 1)];
				}
			} else {
				float *out = po + size_t(a) * w * 2;
				for (int b = 0; b < w; b++) {
					const int gj = std::min(std::max(j0 + b * s, 0), nj - 1);
					out[2 * b] = l[gj];
					out[2 * b + 1] = ReliefHD::hauteur_tri(ph, nx, nz, double(gj) / k, double(gi) / k);
				}
			}
		}
		sortie.append(o);
	}
	return sortie;
}

PackedByteArray ReliefHD::normales_couche(const PackedFloat32Array &hn, int nj, int ni, int ti, int tj, int taille, int marge,
		double px, double pz) const {
	PackedByteArray sortie;
	const float *ps = hn.ptr();
	const float ax = float(0.5 / px);
	const float az = float(0.5 / pz);
	std::vector<uint8_t> r(size_t(taille) * taille), g(size_t(taille) * taille);
	for (int a = 0; a < taille; a++) {
		const int64_t i = std::min<int64_t>(std::max<int64_t>(int64_t(ti) + a - marge, 0), int64_t(ni) - 1);
		const int64_t im = std::max<int64_t>(i - 1, 0);
		const int64_t ip = std::min<int64_t>(i + 1, int64_t(ni) - 1);
		const float *l = ps + i * nj;
		const float *lm = ps + im * nj;
		const float *lp = ps + ip * nj;
		uint8_t *pr = r.data() + size_t(a) * taille;
		uint8_t *pg = g.data() + size_t(a) * taille;
		for (int b = 0; b < taille; b++) {
			const int64_t j = std::min<int64_t>(std::max<int64_t>(int64_t(tj) + b - marge, 0), int64_t(nj) - 1);
			const int64_t jm = std::max<int64_t>(j - 1, 0);
			const int64_t jp = std::min<int64_t>(j + 1, int64_t(nj) - 1);
			const float gx = (l[jp] - l[jm]) * ax;
			const float gz = (lp[j] - lm[j]) * az;
			const float inv = 1.0f / std::sqrt(gx * gx + gz * gz + 1.0f);
			pr[b] = uint8_t(std::lround(std::min(std::max(-gx * inv * 127.5f + 127.5f, 0.0f), 255.0f)));
			pg[b] = uint8_t(std::lround(std::min(std::max(-gz * inv * 127.5f + 127.5f, 0.0f), 255.0f)));
		}
	}
	sortie.resize(taille_bc5(taille));
	uint8_t *o = sortie.ptrw();
	int w = taille;
	uint8_t vr[16], vg[16];
	for (;;) {
		const int nb = std::max((w + 3) / 4, 1);
		for (int bi = 0; bi < nb; bi++) {
			for (int bj = 0; bj < nb; bj++) {
				for (int a = 0; a < 4; a++) {
					const int ia = std::min(bi * 4 + a, w - 1);
					for (int b = 0; b < 4; b++) {
						const int jb = std::min(bj * 4 + b, w - 1);
						vr[a * 4 + b] = r[size_t(ia) * w + jb];
						vg[a * 4 + b] = g[size_t(ia) * w + jb];
					}
				}
				bloc_bc4(vr, o);
				bloc_bc4(vg, o + 8);
				o += 16;
			}
		}
		if (w == 1) {
			break;
		}
		const int w2 = std::max(w / 2, 1);
		for (int a = 0; a < w2; a++) {
			for (int b = 0; b < w2; b++) {
				const size_t c = size_t(a * 2) * w + b * 2;
				r[size_t(a) * w2 + b] = uint8_t((r[c] + r[c + 1] + r[c + w] + r[c + w + 1] + 2) >> 2);
				g[size_t(a) * w2 + b] = uint8_t((g[c] + g[c + 1] + g[c + w] + g[c + w + 1] + 2) >> 2);
			}
		}
		w = w2;
	}
	return sortie;
}

Array ReliefHD::couches(const String &chemin) const {
	Array sortie;
	Ref<FileAccess> f = FileAccess::open(chemin, FileAccess::READ);
	if (f.is_null()) {
		return sortie;
	}
	const PackedByteArray b_tete = f->get_buffer(32);
	if (b_tete.size() != 32 || std::memcmp(b_tete.ptr(), "PNOH", 4) != 0) {
		return sortie;
	}
	uint32_t champs[7];
	std::memcpy(champs, b_tete.ptr() + 4, 28);
	const int64_t nb = int64_t(champs[1]) * champs[2];
	const PackedByteArray b_index = f->get_buffer(nb * 16);
	if (b_index.size() != nb * 16) {
		return sortie;
	}
	const uint64_t corps = uint64_t(32) + uint64_t(nb) * 16;
	std::vector<PackedByteArray> c(static_cast<size_t>(nb));
	std::atomic<int> erreurs(0);
	en_parallele(nb, [&](int64_t q) {
		uint64_t pos;
		uint32_t taille, brut;
		std::memcpy(&pos, b_index.ptr() + q * 16, 8);
		std::memcpy(&taille, b_index.ptr() + q * 16 + 8, 4);
		std::memcpy(&brut, b_index.ptr() + q * 16 + 12, 4);
		Ref<FileAccess> fk = FileAccess::open(chemin, FileAccess::READ);
		if (fk.is_null()) {
			erreurs++;
			return;
		}
		fk->seek(corps + pos);
		const PackedByteArray z = fk->get_buffer(taille);
		c[size_t(q)] = z.decompress(brut, FileAccess::COMPRESSION_ZSTD);
		if (c[size_t(q)].size() != int64_t(brut)) {
			erreurs++;
		}
	});
	if (erreurs.load() > 0) {
		return sortie;
	}
	sortie.append(int(champs[6]));
	sortie.append(int(champs[4]));
	for (const PackedByteArray &o : c) {
		sortie.append(o);
	}
	return sortie;
}

Array ReliefHD::normales(const PackedFloat32Array &hn, int nj, int ni, int tuile, int taille, int marge, double px, double pz) const {
	const int nl = (ni - 1 + tuile - 1) / tuile;
	const int nc = (nj - 1 + tuile - 1) / tuile;
	std::vector<PackedByteArray> c(size_t(nl) * nc);
	en_parallele(int64_t(nl) * nc, [&](int64_t q) {
		c[size_t(q)] = normales_couche(hn, nj, ni, int(q / nc) * tuile, int(q % nc) * tuile, taille, marge, px, pz);
	});
	Array sortie;
	for (const PackedByteArray &o : c) {
		sortie.append(o);
	}
	return sortie;
}
