#include "noyau_decor.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cmath>
#include <limits>

using namespace godot;

void NoyauDecor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_pieces", "pieces"), &NoyauDecor::set_pieces);
	ClassDB::bind_method(D_METHOD("piece_grille", "rp", "pas", "nx", "nz"), &NoyauDecor::piece_grille);
	ClassDB::bind_method(D_METHOD("completer_tri", "h", "nans", "rp", "pas", "nx", "grille", "nxg", "nzg", "x_ouest",
								 "z_nord", "dx", "dz", "pasg", "fine", "ncx", "ncz", "lx", "lz"),
			&NoyauDecor::completer_tri);
	ClassDB::bind_method(D_METHOD("piece_faces", "rp", "pas", "nx", "nz", "h", "trou"), &NoyauDecor::piece_faces);
}

void NoyauDecor::set_pieces(const Array &p_pieces) {
	pieces.clear();
	for (int64_t k = 0; k < p_pieces.size(); k++) {
		const Array e = p_pieces[k];
		Piece p;
		p.r = e[0];
		p.nx = e[1];
		p.nz = e[2];
		p.hs = e[3];
		p.masque = e[4];
		p.mw = e[5];
		p.mh = e[6];
		pieces.push_back(p);
	}
}

static inline int clampi(int v, int a, int b) {
	return v < a ? a : (v > b ? b : v);
}

static inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;
}

double NoyauDecor::terrain_piece(double x, double z, bool &trou) const {
	for (const Piece &p : pieces) {
		if (!p.r.has_point(Vector2(real_t(x), real_t(z)))) {
			continue;
		}
		const double fx = (x - p.r.position.x) / p.r.size.x * (p.nx - 1);
		const double fz = (z - p.r.position.y) / p.r.size.y * (p.nz - 1);
		const int j = clampi(int(fx), 0, p.nx - 2);
		const int i = clampi(int(fz), 0, p.nz - 2);
		const double u = fx - j;
		const double v = fz - i;
		const float *hs = p.hs.ptr();
		const double h = lerpd(lerpd(hs[i * p.nx + j], hs[i * p.nx + j + 1], u),
				lerpd(hs[(i + 1) * p.nx + j], hs[(i + 1) * p.nx + j + 1], u), v);
		const int mx = clampi(int((x - p.r.position.x) * 4.0), 0, p.mw - 1);
		const int mz = clampi(int((z - p.r.position.y) * 4.0), 0, p.mh - 1);
		trou = p.masque[mz * p.mw + mx] >= 128;
		return h;
	}
	trou = false;
	return std::numeric_limits<double>::quiet_NaN();
}

Array NoyauDecor::piece_grille(const Rect2 &rp, double pas, int nx, int nz) const {
	PackedFloat32Array h;
	PackedByteArray trou;
	h.resize((nx + 1) * (nz + 1));
	trou.resize((nx + 1) * (nz + 1));
	PackedInt32Array nans;
	float *hw = h.ptrw();
	uint8_t *tw = trou.ptrw();
	for (int jj = 0; jj <= nz; jj++) {
		for (int ii = 0; ii <= nx; ii++) {
			const double x = rp.position.x + ii * pas;
			const double z = rp.position.y + jj * pas;
			bool t = false;
			const double hh = terrain_piece(x, z, t);
			hw[jj * (nx + 1) + ii] = float(hh);
			tw[jj * (nx + 1) + ii] = t ? 1 : 0;
			if (std::isnan(hh)) {
				nans.append(jj * (nx + 1) + ii);
			}
		}
	}
	Array r;
	r.append(h);
	r.append(trou);
	r.append(nans);
	return r;
}

PackedVector3Array NoyauDecor::piece_faces(const Rect2 &rp, double pas, int nx, int nz,
		const PackedFloat32Array &h, const PackedByteArray &trou) const {
	PackedVector3Array f;
	if (h.size() != (nx + 1) * (nz + 1) || trou.size() != h.size()) {
		return f;
	}
	std::vector<Vector3> v;
	v.reserve(size_t(nx) * nz * 6);
	const float *hp = h.ptr();
	const uint8_t *tp = trou.ptr();
	for (int jj = 0; jj < nz; jj++) {
		for (int ii = 0; ii < nx; ii++) {
			const int a = jj * (nx + 1) + ii;
			const int b = a + 1;
			const int c3 = a + nx + 1;
			const int d = c3 + 1;
			const double xa = rp.position.x + ii * pas;
			const double za = rp.position.y + jj * pas;
			if (tp[a] + tp[b] + tp[c3] + tp[d] > 0) {
				bool t = false;
				terrain_piece(xa + pas * 0.5, za + pas * 0.5, t);
				if (t) {
					continue;
				}
			}
			const real_t x0 = real_t(xa), x1 = real_t(xa + pas), z0 = real_t(za), z1 = real_t(za + pas);
			v.push_back(Vector3(x0, hp[a], z0));
			v.push_back(Vector3(x1, hp[b], z0));
			v.push_back(Vector3(x0, hp[c3], z1));
			v.push_back(Vector3(x1, hp[b], z0));
			v.push_back(Vector3(x1, hp[d], z1));
			v.push_back(Vector3(x0, hp[c3], z1));
		}
	}
	f.resize(int64_t(v.size()));
	Vector3 *fw = f.ptrw();
	for (size_t k = 0; k < v.size(); k++) {
		fw[k] = v[k];
	}
	return f;
}

Array NoyauDecor::completer_tri(const PackedFloat32Array &h, const PackedInt32Array &nans, const Rect2 &rp, double pas,
		int nx, const PackedFloat32Array &grille, int nxg, int nzg, double x_ouest, double z_nord, double dx, double dz,
		int pasg, const PackedByteArray &fine, int ncx, int ncz, double lx, double lz) const {
	PackedFloat32Array out = h;
	PackedInt32Array reste;
	float *ow = out.ptrw();
	const float *g = grille.ptr();
	const int lim_x = nxg - 1;
	const int lim_z = nzg - 1;
	for (int64_t q = 0; q < nans.size(); q++) {
		const int k = nans[q];
		const double x = rp.position.x + (k % (nx + 1)) * pas;
		const double z = rp.position.y + (k / (nx + 1)) * pas;
		if (!fine.is_empty()) {
			// ReliefFin.fine_ici
			const int cj = int(std::floor((x - x_ouest) / lx));
			const int ci = int(std::floor((z - z_nord) / lz));
			if (cj >= 0 && ci >= 0 && cj < ncx && ci < ncz && fine[ci * ncx + cj] == 1) {
				reste.append(k);
				continue;
			}
		}
		double fx = (x - x_ouest) / dx;
		fx = fx < 0.0 ? 0.0 : (fx > lim_x - 0.001 ? lim_x - 0.001 : fx);
		fx /= pasg;
		double fz = (z - z_nord) / dz;
		fz = fz < 0.0 ? 0.0 : (fz > lim_z - 0.001 ? lim_z - 0.001 : fz);
		fz /= pasg;
		const int j0 = int(fx) * pasg;
		const int i0 = int(fz) * pasg;
		const double wx = fx - int(fx);
		const double wz = fz - int(fz);
		const int j1 = j0 + pasg < lim_x ? j0 + pasg : lim_x;
		const int i1 = i0 + pasg < lim_z ? i0 + pasg : lim_z;
		const double a = g[i0 * nxg + j0];
		const double b = g[i0 * nxg + j1];
		const double cc = g[i1 * nxg + j0];
		const double d = g[i1 * nxg + j1];
		double r;
		if (wx + wz <= 1.0) {
			r = a + (b - a) * wx + (cc - a) * wz;
		} else {
			r = d + (cc - d) * (1.0 - wx) + (b - d) * (1.0 - wz);
		}
		ow[k] = float(r);
	}
	Array res;
	res.append(out);
	res.append(reste);
	return res;
}
