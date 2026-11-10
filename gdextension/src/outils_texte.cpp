#include "outils_texte.h"

#include "polypartition.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/text_server.hpp>
#include <godot_cpp/classes/text_server_manager.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <map>
#include <utility>

using namespace godot;

void OutilsTexte::_bind_methods() {
	ClassDB::bind_method(D_METHOD("maillage", "font", "texte", "taille", "pixel", "pas_courbe", "aligne", "langue"),
			&OutilsTexte::maillage);
}

namespace {

// (mêmes structures que TextMesh)
struct ContourPoint {
	Vector2 point;
	bool sharp = false;
	ContourPoint() {}
	ContourPoint(const Vector2 &p_pt, bool p_sharp) {
		point = p_pt;
		sharp = p_sharp;
	}
};

struct GlyphMeshData {
	Vector<Vector2> triangles;
	Vector<Vector<ContourPoint>> contours;
	Vector2 min_p = Vector2(Math_INF, Math_INF);
	Vector2 max_p = Vector2(-Math_INF, -Math_INF);
};

struct Glyphe {
	int64_t index = 0;
	RID font_rid;
	int64_t font_size = 0;
	float x_off = 0.0f;
	float y_off = 0.0f;
	float advance = 0.0f;
	int repeat = 1;
};

// TextMesh::_generate_glyph_mesh_data, sans les données des flancs (profondeur nulle)
bool generer_glyphe(TextServer *ts, GlyphMeshData &gl_data, const Glyphe &p_gl, real_t pixel_size, real_t curve_step) {
	Dictionary d = ts->font_get_glyph_contours(p_gl.font_rid, p_gl.font_size, p_gl.index);

	PackedVector3Array points = d["points"];
	PackedInt32Array contours = d["contours"];
	bool orientation = d["orientation"];

	if (points.size() < 3 || contours.is_empty()) {
		return true;
	}

	for (int i = 0; i < contours.size(); i++) {
		int32_t start = (i == 0) ? 0 : (contours[i - 1] + 1);
		int32_t end = contours[i];
		Vector<ContourPoint> polygon;

		for (int32_t j = start; j <= end; j++) {
			if (points[j].z == (real_t)TextServer::CONTOUR_CURVE_TAG_ON) {
				Vector2 p = Vector2(points[j].x, points[j].y) * pixel_size;
				polygon.push_back(ContourPoint(p, true));
			} else if (points[j].z == (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CONIC) {
				int32_t next = (j == end) ? start : (j + 1);
				int32_t prev = (j == start) ? end : (j - 1);
				Vector2 p0;
				Vector2 p1 = Vector2(points[j].x, points[j].y);
				Vector2 p2;

				if (points[prev].z == (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CONIC) {
					p0 = (Vector2(points[prev].x, points[prev].y) + Vector2(points[j].x, points[j].y)) / 2.0;
				} else if (points[prev].z == (real_t)TextServer::CONTOUR_CURVE_TAG_ON) {
					p0 = Vector2(points[prev].x, points[prev].y);
				} else {
					return false;
				}
				if (points[next].z == (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CONIC) {
					p2 = (Vector2(points[j].x, points[j].y) + Vector2(points[next].x, points[next].y)) / 2.0;
				} else if (points[next].z == (real_t)TextServer::CONTOUR_CURVE_TAG_ON) {
					p2 = Vector2(points[next].x, points[next].y);
				} else {
					return false;
				}

				real_t step = CLAMP(curve_step / (p0 - p2).length(), 0.01, 0.5);
				real_t t = step;
				while (t < 1.0) {
					real_t omt = (1.0 - t);
					real_t omt2 = omt * omt;
					real_t t2 = t * t;

					Vector2 point = p1 + omt2 * (p0 - p1) + t2 * (p2 - p1);
					Vector2 p = point * pixel_size;
					polygon.push_back(ContourPoint(p, false));
					t += step;
				}
			} else if (points[j].z == (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CUBIC) {
				int32_t cur = j;
				int32_t next1 = (j == end) ? start : (j + 1);
				int32_t next2 = (next1 == end) ? start : (next1 + 1);
				int32_t prev = (j == start) ? end : (j - 1);

				if (points[prev].z != (real_t)TextServer::CONTOUR_CURVE_TAG_ON) {
					cur = (cur == 0) ? end : cur - 1;
					next1 = (next1 == 0) ? end : next1 - 1;
					next2 = (next2 == 0) ? end : next2 - 1;
					prev = (prev == 0) ? end : prev - 1;
				} else {
					j++;
				}
				if (points[prev].z != (real_t)TextServer::CONTOUR_CURVE_TAG_ON ||
						points[cur].z != (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CUBIC ||
						points[next1].z != (real_t)TextServer::CONTOUR_CURVE_TAG_OFF_CUBIC ||
						points[next2].z != (real_t)TextServer::CONTOUR_CURVE_TAG_ON) {
					return false;
				}

				Vector2 p0 = Vector2(points[prev].x, points[prev].y);
				Vector2 p1 = Vector2(points[cur].x, points[cur].y);
				Vector2 p2 = Vector2(points[next1].x, points[next1].y);
				Vector2 p3 = Vector2(points[next2].x, points[next2].y);

				real_t step = CLAMP(curve_step / (p0 - p3).length(), 0.01, 0.5);
				real_t t = step;
				while (t < 1.0) {
					Vector2 point = p0.bezier_interpolate(p1, p2, p3, t);
					Vector2 p = point * pixel_size;
					polygon.push_back(ContourPoint(p, false));
					t += step;
				}
			} else {
				return false;
			}
		}

		if (polygon.size() < 3) {
			continue;
		}

		if (!orientation) {
			polygon.reverse();
		}

		gl_data.contours.push_back(polygon);
	}

	List<TPPLPoly> in_poly;
	for (int i = 0; i < gl_data.contours.size(); i++) {
		TPPLPoly inp;
		inp.Init(gl_data.contours[i].size());
		for (int j = 0; j < gl_data.contours[i].size(); j++) {
			gl_data.min_p = gl_data.min_p.min(gl_data.contours[i][j].point);
			gl_data.max_p = gl_data.max_p.max(gl_data.contours[i][j].point);
			inp.GetPoint(j) = gl_data.contours[i][j].point;
		}
		TPPLOrientation poly_orient = inp.GetOrientation();
		if (poly_orient == TPPL_ORIENTATION_CW) {
			inp.SetHole(true);
		}
		in_poly.push_back(inp);
	}

	TPPLPartition tpart;
	List<TPPLPoly> out_poly;
	if (tpart.ConvexPartition_HM(&in_poly, &out_poly) == 0) {
		return false;
	}
	List<TPPLPoly> out_tris;
	for (TPPLPoly &tp : out_poly) {
		if (tpart.Triangulate_OPT(&tp, &out_tris) == 0) {
			return false;
		}
	}

	for (const TPPLPoly &tp : out_tris) {
		if (tp.GetNumPoints() != 3) {
			return false;
		}
		for (int i = 0; i < 3; i++) {
			gl_data.triangles.push_back(Vector2(tp.GetPoint(i).x, tp.GetPoint(i).y));
		}
	}
	return true;
}

// Aller-retour des normales et tangentes par la compression du serveur de rendu (RenderingServer, octaèdre sur
// 2 × 16 bits) : le TextMesh relu les rendait ainsi ((-1,5e-5, -1,5e-5, 1) pour (0, 0, 1)), à l'octet près.
Vector3 normale_serveur(const Vector3 &n) {
	Vector2 res = n.octahedron_encode();
	uint16_t v[2] = { (uint16_t)CLAMP(res.x * 65535, 0, 65535), (uint16_t)CLAMP(res.y * 65535, 0, 65535) };
	return Vector3::octahedron_decode(Vector2(v[0] / 65535.0, v[1] / 65535.0));
}

void tangente_serveur(float *t) {
	const Vector3 src(t[0], t[1], t[2]);
	Vector2 res = src.octahedron_tangent_encode(t[3]);
	uint16_t v[2] = { (uint16_t)CLAMP(res.x * 65535, 0, 65535), (uint16_t)CLAMP(res.y * 65535, 0, 65535) };
	if (v[0] == 0 && v[1] == 65535) {
		v[0] = 65535;
	}
	float sign;
	Vector3 r = Vector3::octahedron_tangent_decode(Vector2(v[0] / 65535.0, v[1] / 65535.0), &sign);
	t[0] = r.x;
	t[1] = r.y;
	t[2] = r.z;
	t[3] = sign;
}

} // namespace

Array OutilsTexte::maillage(const Ref<Font> &font, const String &texte, int64_t taille, double pixel, double pas_courbe,
		int64_t aligne, const String &langue) const {
	if (font.is_null() || aligne < 0 || aligne > 2) {
		return Array();
	}
	Ref<TextServer> ts_ref = TextServerManager::get_singleton()->get_primary_interface();
	TextServer *TS = ts_ref.ptr();
	const real_t pixel_size = (real_t)pixel;
	const real_t curve_step = (real_t)pas_courbe;
	const float width = 500.0;
	const float line_spacing = 0.f;
	const Point2 lbl_offset;
	const int font_size = (int)taille;

	RID text_rid = TS->create_shaped_text();
	TS->shaped_text_set_direction(text_rid, TextServer::DIRECTION_AUTO);
	TS->shaped_text_add_string(text_rid, texte, font->get_rids(), font_size, font->get_opentype_features(), langue);
	TypedArray<Vector3i> stt = TS->parse_structured_text(TextServer::STRUCTURED_TEXT_DEFAULT, Array(), texte);
	TS->shaped_text_set_bidi_override(text_rid, stt);

	Vector<RID> lines_rid;
	PackedInt32Array line_breaks = TS->shaped_text_get_line_breaks(text_rid, width, 0, TextServer::BREAK_MANDATORY);
	for (int i = 0; i < line_breaks.size(); i = i + 2) {
		RID line = TS->shaped_text_substr(text_rid, line_breaks[i], line_breaks[i + 1] - line_breaks[i]);
		lines_rid.push_back(line);
	}

	// glyphes de chaque ligne (copiés des dictionnaires du serveur de texte)
	Vector<Vector<Glyphe>> glyphes;
	for (int i = 0; i < lines_rid.size(); i++) {
		TypedArray<Dictionary> g = TS->shaped_text_get_glyphs(lines_rid[i]);
		Vector<Glyphe> l;
		for (int64_t j = 0; j < g.size(); j++) {
			Dictionary dg = g[j];
			Glyphe e;
			e.index = dg["index"];
			e.font_rid = dg["font_rid"];
			e.font_size = dg["font_size"];
			const Vector2 of = dg["offset"];
			e.x_off = of.x;
			e.y_off = of.y;
			e.advance = (float)(double)dg["advance"];
			e.repeat = (int)(int64_t)dg["repeat"];
			l.push_back(e);
		}
		glyphes.push_back(l);
	}

	float total_h = 0.0;
	for (int i = 0; i < lines_rid.size(); i++) {
		total_h += (TS->shaped_text_get_size(lines_rid[i]).y + line_spacing) * pixel_size;
	}
	float vbegin = (total_h - line_spacing * pixel_size) / 2.0;     // (alignement vertical centré)

	// (clé du moteur : police et numéro du glyphe)
	std::map<std::pair<uint64_t, int64_t>, GlyphMeshData> cache;
	bool echec = false;
	auto donnees = [&](const Glyphe &g) -> GlyphMeshData & {
		const std::pair<uint64_t, int64_t> cle(uint64_t(g.font_rid.get_id()), g.index);
		auto it = cache.find(cle);
		if (it == cache.end()) {
			it = cache.emplace(cle, GlyphMeshData()).first;
			if (!generer_glyphe(TS, it->second, g, pixel_size, curve_step)) {
				echec = true;
			}
		}
		return it->second;
	};

	Vector2 min_p = Vector2(Math_INF, Math_INF);
	Vector2 max_p = Vector2(-Math_INF, -Math_INF);
	int32_t p_size = 0;
	int32_t i_size = 0;

	Vector2 offset = Vector2(0, vbegin + lbl_offset.y * pixel_size);
	for (int i = 0; i < lines_rid.size(); i++) {
		const Vector<Glyphe> &gl = glyphes[i];
		float line_width = TS->shaped_text_get_width(lines_rid[i]) * pixel_size;
		switch (aligne) {
			case 0:
				offset.x = 0.0;
				break;
			case 1:
				offset.x = -line_width / 2.0;
				break;
			case 2:
				offset.x = -line_width;
				break;
		}
		offset.x += lbl_offset.x * pixel_size;
		offset.y -= TS->shaped_text_get_ascent(lines_rid[i]) * pixel_size;
		for (int j = 0; j < gl.size(); j++) {
			if (gl[j].index == 0) {
				offset.x += gl[j].advance * pixel_size * gl[j].repeat;
				continue;
			}
			if (gl[j].font_rid != RID()) {
				GlyphMeshData &gl_data = donnees(gl[j]);
				const Vector2 gl_of = Vector2(gl[j].x_off, gl[j].y_off) * pixel_size;
				p_size += gl[j].repeat * gl_data.triangles.size();
				i_size += gl[j].repeat * gl_data.triangles.size();
				for (int r = 0; r < gl[j].repeat; r++) {
					min_p.x = MIN(gl_data.min_p.x + offset.x + gl_of.x, min_p.x);
					min_p.y = MIN(gl_data.min_p.y - offset.y + gl_of.y, min_p.y);
					max_p.x = MAX(gl_data.max_p.x + offset.x + gl_of.x, max_p.x);
					max_p.y = MAX(gl_data.max_p.y - offset.y + gl_of.y, max_p.y);
					offset.x += gl[j].advance * pixel_size;
				}
			} else {
				p_size += gl[j].repeat * 4;
				i_size += gl[j].repeat * 6;
				offset.x += gl[j].advance * pixel_size * gl[j].repeat;
			}
		}
		offset.y -= (TS->shaped_text_get_descent(lines_rid[i]) + line_spacing) * pixel_size;
	}

	PackedVector3Array vertices, normals;
	PackedFloat32Array tangents;
	PackedVector2Array uvs;
	PackedInt32Array indices;
	vertices.resize(p_size);
	normals.resize(p_size);
	uvs.resize(p_size);
	tangents.resize(p_size * 4);
	indices.resize(i_size);
	Vector3 *vertices_ptr = vertices.ptrw();
	Vector3 *normals_ptr = normals.ptrw();
	float *tangents_ptr = tangents.ptrw();
	Vector2 *uvs_ptr = uvs.ptrw();
	int32_t *indices_ptr = indices.ptrw();
	int32_t p_idx = 0;
	int32_t i_idx = 0;
	const real_t depth = 0.0;

	offset = Vector2(0, vbegin + lbl_offset.y * pixel_size);
	for (int i = 0; i < lines_rid.size() && !echec; i++) {
		const Vector<Glyphe> &gl = glyphes[i];
		float line_width = TS->shaped_text_get_width(lines_rid[i]) * pixel_size;
		switch (aligne) {
			case 0:
				offset.x = 0.0;
				break;
			case 1:
				offset.x = -line_width / 2.0;
				break;
			case 2:
				offset.x = -line_width;
				break;
		}
		offset.x += lbl_offset.x * pixel_size;
		offset.y -= TS->shaped_text_get_ascent(lines_rid[i]) * pixel_size;
		for (int j = 0; j < gl.size(); j++) {
			if (gl[j].index == 0) {
				offset.x += gl[j].advance * pixel_size * gl[j].repeat;
				continue;
			}
			if (gl[j].font_rid != RID()) {
				const GlyphMeshData &gl_data = donnees(gl[j]);
				int64_t tsz = gl_data.triangles.size();
				const Vector2 *ts_ptr = gl_data.triangles.ptr();
				const Vector2 gl_of = Vector2(gl[j].x_off, gl[j].y_off) * pixel_size;
				for (int r = 0; r < gl[j].repeat; r++) {
					for (int k = 0; k < tsz; k += 3) {
						for (int l = 0; l < 3; l++) {
							Vector3 point = Vector3(ts_ptr[k + l].x + offset.x + gl_of.x, -ts_ptr[k + l].y + offset.y - gl_of.y, depth / 2.0);
							vertices_ptr[p_idx] = point;
							normals_ptr[p_idx] = Vector3(0.0, 0.0, 1.0);
							uvs_ptr[p_idx] = Vector2(Math::remap(point.x, min_p.x, max_p.x, real_t(0.0), real_t(1.0)), Math::remap(point.y, -max_p.y, -min_p.y, real_t(1.0), real_t(0.0)));
							tangents_ptr[p_idx * 4 + 0] = 1.0;
							tangents_ptr[p_idx * 4 + 1] = 0.0;
							tangents_ptr[p_idx * 4 + 2] = 0.0;
							tangents_ptr[p_idx * 4 + 3] = 1.0;
							indices_ptr[i_idx++] = p_idx;
							p_idx++;
						}
					}
					offset.x += gl[j].advance * pixel_size;
				}
			} else {
				for (int r = 0; r < gl[j].repeat; r++) {
					Size2 sz = TS->get_hex_code_box_size(gl[j].font_size, gl[j].index) * pixel_size;
					Vector3 quad_faces[4] = {
						Vector3(offset.x, offset.y, 0.0),
						Vector3(offset.x, sz.y + offset.y, 0.0),
						Vector3(sz.x + offset.x, sz.y + offset.y, 0.0),
						Vector3(sz.x + offset.x, offset.y, 0.0),
					};
					for (int k = 0; k < 4; k++) {
						vertices_ptr[p_idx + k] = quad_faces[k];
						normals_ptr[p_idx + k] = Vector3(0.0, 0.0, 1.0);
						uvs_ptr[p_idx + k] = Vector2(Math::remap(quad_faces[k].x, min_p.x, max_p.x, real_t(0.0), real_t(1.0)), Math::remap(quad_faces[k].y, -max_p.y, -min_p.y, real_t(1.0), real_t(0.0)));
						tangents_ptr[(p_idx + k) * 4 + 0] = 1.0;
						tangents_ptr[(p_idx + k) * 4 + 1] = 0.0;
						tangents_ptr[(p_idx + k) * 4 + 2] = 0.0;
						tangents_ptr[(p_idx + k) * 4 + 3] = 1.0;
					}
					indices_ptr[i_idx++] = p_idx;
					indices_ptr[i_idx++] = p_idx + 1;
					indices_ptr[i_idx++] = p_idx + 2;
					indices_ptr[i_idx++] = p_idx + 0;
					indices_ptr[i_idx++] = p_idx + 2;
					indices_ptr[i_idx++] = p_idx + 3;
					p_idx += 4;
					offset.x += gl[j].advance * pixel_size;
				}
			}
		}
		offset.y -= (TS->shaped_text_get_descent(lines_rid[i]) + line_spacing) * pixel_size;
	}

	for (int i = 0; i < lines_rid.size(); i++) {
		TS->free_rid(lines_rid[i]);
	}
	TS->free_rid(text_rid);
	if (echec) {
		return Array();             // (glyphe refusé : le GDScript passe par le TextMesh)
	}

	if (indices.is_empty()) {
		vertices.push_back(Vector3());
		normals.push_back(Vector3());
		uvs.push_back(Vector2());
		tangents.push_back(1.0);
		tangents.push_back(0.0);
		tangents.push_back(0.0);
		tangents.push_back(1.0);
		indices.push_back(0);
		indices.push_back(0);
		indices.push_back(0);
	}

	{
		Vector3 *wn = normals.ptrw();
		float *wt = tangents.ptrw();
		for (int64_t k = 0; k < normals.size(); k++) {
			wn[k] = normale_serveur(wn[k]);
			tangente_serveur(wt + k * 4);
		}
	}

	Array arr;
	arr.resize(Mesh::ARRAY_MAX);
	arr[Mesh::ARRAY_VERTEX] = vertices;
	arr[Mesh::ARRAY_NORMAL] = normals;
	arr[Mesh::ARRAY_TANGENT] = tangents;
	arr[Mesh::ARRAY_TEX_UV] = uvs;
	arr[Mesh::ARRAY_INDEX] = indices;
	return arr;
}
