// Still water that catches the light. Blender's "Water" material supplies the color
// and smoothness; this tilts the surface normal by the slopes of three small waves,
// so the sky's reflection and the sun's glint wobble while nothing actually moves.
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.1, 0.35, 0.45);
uniform float roughness = 0.08;

varying vec2 ground; // world x and z, so ripples run across tiles without seams

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = ground;
	float t = TIME;
	// Each wave is sin(k . p + w t); its slope is k cos(k . p + w t).
	vec2 slope = vec2(4.0, 0.0) * cos(4.0 * p.x + 1.3 * t) * 0.025;
	slope += vec2(0.0, 3.3) * cos(3.3 * p.y - 1.1 * t) * 0.025;
	vec2 k = vec2(5.1, -4.3);
	slope += k * cos(dot(k, p) + 2.0 * t) * 0.012;
	vec3 up = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(up, 0.0)).xyz);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.7;
}
