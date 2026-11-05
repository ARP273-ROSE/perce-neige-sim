class_name CielAlpin
extends RefCounted
## Ciel du PC (rendu Vulkan) : bleu d'altitude, horizon clair, soleil et quelques nuages, immobiles
## (TIME referait les textures de reflets à chaque image).
## Le ciel physique sans soleil allumé sortait gris terne. Son éclairage reste celui d'avant :
## la passe qui nourrit l'ambiance et les reflets rend une couleur fixe, sans nuages.

const CODE: String = """shader_type sky;
uniform vec3 haut = vec3(0.13, 0.30, 0.66);
uniform vec3 horizon = vec3(0.62, 0.74, 0.90);
uniform vec3 sol = vec3(0.55, 0.58, 0.62);
uniform vec3 ambiance = vec3(0.13, 0.15, 0.18);
uniform vec3 soleil = vec3(0.40, 0.78, 0.48);
uniform float energie = 1.0;
uniform float nuages = 1.0;
// (hachage entier : le « fract(sin(...)) » habituel variait d'un coin de cellule à l'autre et laissait des arêtes droites)
float h2(vec2 p) {
	uint x = uint(int(p.x)) * 1664525u + uint(int(p.y)) * 1013904223u;
	x = (x ^ (x >> 15u)) * 2654435769u;
	x = x ^ (x >> 13u);
	return float(x & 16777215u) / 16777215.0;
}
float b2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * b2(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v;
}
void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = (EYEDIR.y < 0.0 ? sol : ambiance) * energie;
	} else {
		float y = EYEDIR.y;
		vec3 c = mix(horizon, haut, 1.0 - exp(-max(y, 0.0) * 3.2));
		vec3 s = normalize(soleil);
		float d = max(dot(EYEDIR, s), 0.0);
		c += vec3(1.0, 0.96, 0.88) * (pow(d, 12.0) * 0.10 + pow(d, 180.0) * 0.5 + smoothstep(0.99985, 0.99995, d) * 8.0);
		if (nuages > 0.0 && y > 0.005) {
			vec2 q = EYEDIR.xz / (y + 0.14) * 0.9 + vec2(40.0, 40.0);
			float f = fbm(q);
			float m = smoothstep(0.50, 0.78, f) * smoothstep(0.01, 0.16, y) * nuages;
			vec3 blanc = mix(vec3(0.72, 0.76, 0.82), vec3(1.05, 1.04, 1.02), smoothstep(0.55, 0.85, fbm(q + s.xz * 0.12)));
			c = mix(c, blanc, m * 0.85);
		}
		c = mix(sol, c, smoothstep(-0.015, 0.002, y));
		COLOR = c * energie;
	}
}
"""


static func materiau(sol: Color, soleil: Vector3) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = CODE
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sol", Vector3(sol.r, sol.g, sol.b))
	m.set_shader_parameter("soleil", soleil)
	return m
