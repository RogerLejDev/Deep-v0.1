// Shared procedural noise. World-space so detail is continuous across chunk
// borders and never reveals the tile grid.

float deep_hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

float deep_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = deep_hash21(i);
	float b = deep_hash21(i + vec2(1.0, 0.0));
	float c = deep_hash21(i + vec2(0.0, 1.0));
	float d = deep_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float deep_fbm(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) break;
		v += amp * deep_vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.1);
		amp *= 0.5;
	}
	return v;
}

// Ridged variant, used for fibrous/organic materials and crystal facets.
float deep_ridged(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) break;
		v += amp * (1.0 - abs(deep_vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + vec2(3.7, 19.2);
		amp *= 0.5;
	}
	return v;
}
