// Molten rock under a cracked crust. Blender's "Lava" material supplies the colors; this adds
// motion with a few sine waves in world space, so neighboring tiles flow as one pool
// and no texture is needed. game/stage.gd swaps it in by the material's name.
shader_type spatial;

uniform vec3 albedo : source_color = vec3(1.0, 0.4, 0.1);
uniform vec3 glow : source_color = vec3(1.0, 0.3, 0.04);
uniform float energy = 2.0;
uniform float roughness = 0.6;

varying vec2 ground; // world x and z: the same spot gets the same heat on any tile

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = ground;
	float t = TIME;
	// Warp the plane a little, then light the lines where a grid of sines crosses zero:
	// wandering cracks between plates of crust, drifting as the warp moves.
	vec2 q = p + 0.4 * vec2(sin(p.y * 2.3 + t * 0.5), sin(p.x * 1.9 - t * 0.4));
	float cracks = pow(1.0 - abs(sin(q.x * 2.6) * sin(q.y * 2.6)), 7.0);
	float swell = 0.5 + 0.5 * sin(p.x * 0.9 + t * 0.7) * sin(p.y * 0.7 - t * 0.5);
	float heat = clamp(cracks + 0.35 * swell, 0.0, 1.0); // 0 is crust, 1 is white-hot
	ALBEDO = albedo * mix(0.15, 1.0, heat);
	EMISSION = glow * energy * mix(0.06, 1.0, heat * heat);
	ROUGHNESS = mix(0.95, roughness, heat);
}
