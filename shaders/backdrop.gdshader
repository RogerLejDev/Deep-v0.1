shader_type canvas_item;
render_mode unshaded, blend_mix;

// Full-screen backdrop: sky and parallax hills above ground, distant cavern
// walls and hanging stalactite silhouettes below it. Everything is procedural
// and anchored to world space, so the layers slide at their own rates as the
// camera moves and never repeat visibly.

#include "res://shaders/noise.gdshaderinc"

uniform vec2 view_origin = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
// World Y of the surface line, and of the world floor.
uniform float surface_y = 1024.0;
uniform float world_bottom_y = 11264.0;
// 0 above ground, 1 deep underground. Cross-fades sky out, caverns in.
uniform float underground = 0.0;
uniform vec3 ambient_light : source_color = vec3(1.0);
uniform vec3 zone_tint : source_color = vec3(0.2, 0.25, 0.35);
uniform float drift = 0.0;

const vec3 SKY_TOP = vec3(0.106, 0.180, 0.275);
const vec3 SKY_MID = vec3(0.278, 0.388, 0.435);
const vec3 SKY_HORIZON = vec3(0.682, 0.600, 0.459);
const vec3 SUN = vec3(1.0, 0.878, 0.690);

// Height of a parallax ridge at layer-space x.
float ridge(float x, float freq, float amp, float base) {
	float h = deep_fbm(vec2(x * freq, 3.7), 3);
	float h2 = deep_fbm(vec2(x * freq * 2.9, 11.1), 2);
	return base - (h * 0.78 + h2 * 0.22) * amp;
}

void fragment() {
	vec2 wp = view_origin + UV * view_size;
	vec3 col = vec3(0.0);

	// ---------------------------------------------------------------- sky ----
	// Vertical gradient keyed to the surface line, not the screen, so the
	// horizon stays put while the camera climbs.
	float sky_t = clamp((surface_y - wp.y) / 900.0, 0.0, 1.0);
	vec3 sky = mix(SKY_HORIZON, SKY_MID, smoothstep(0.0, 0.42, sky_t));
	sky = mix(sky, SKY_TOP, smoothstep(0.35, 1.0, sky_t));

	// A low, hazy sun that gives the surface a direction of light.
	vec2 sun_pos = vec2(view_origin.x + view_size.x * 0.74, surface_y - 560.0);
	float sun_d = length((wp - sun_pos) / vec2(1.0, 0.72));
	sky += SUN * (1.0 - smoothstep(0.0, 120.0, sun_d)) * 0.85;
	sky += SUN * (1.0 - smoothstep(0.0, 760.0, sun_d)) * 0.22;

	// Drifting cloud banding.
	float cloud = deep_fbm(vec2(wp.x * 0.0012 + drift * 0.012, wp.y * 0.004), 3);
	sky += vec3(0.08, 0.07, 0.06) * smoothstep(0.55, 0.95, cloud) * (1.0 - sky_t * 0.3);

	// ------------------------------------------------------- parallax hills --
	// Three ridges, each in its own slower-moving layer space.
	float layer_x[3] = {
		view_origin.x * 0.25 + UV.x * view_size.x,
		view_origin.x * 0.45 + UV.x * view_size.x,
		view_origin.x * 0.68 + UV.x * view_size.x
	};
	float ridge_base[3] = { surface_y - 150.0, surface_y - 86.0, surface_y - 34.0 };
	float ridge_amp[3] = { 210.0, 140.0, 78.0 };
	float ridge_freq[3] = { 0.0016, 0.0029, 0.0051 };
	vec3 ridge_col[3] = {
		vec3(0.192, 0.247, 0.263),
		vec3(0.129, 0.176, 0.192),
		vec3(0.078, 0.110, 0.118)
	};

	for (int i = 0; i < 3; i++) {
		float h = ridge(layer_x[i], ridge_freq[i], ridge_amp[i], ridge_base[i]);
		float m = smoothstep(h - 2.0, h + 2.0, wp.y);
		// Treeline fuzz along the crest so ridges are not clean curves.
		float fuzz = deep_fbm(vec2(layer_x[i] * 0.09, 2.0), 2);
		m = smoothstep(h - 10.0 * fuzz, h + 3.0, wp.y);
		sky = mix(sky, ridge_col[i], m);
	}

	// ---------------------------------------------------- underground walls --
	// Far wall: broad strata bands plus blotchy rock.
	vec2 far = vec2(view_origin.x * 0.35 + UV.x * view_size.x,
			view_origin.y * 0.72 + UV.y * view_size.y);
	float strata = sin(far.y * 0.0115 + deep_fbm(far * 0.004, 2) * 6.0);
	float blotch = deep_fbm(far * 0.0075 + vec2(7.0, 3.0), 3);
	vec3 wall = zone_tint * (0.26 + 0.20 * blotch);
	wall *= 0.86 + 0.22 * smoothstep(-0.2, 0.8, strata);

	// Mid wall: large cavern voids read as a darker silhouette layer.
	vec2 mid = vec2(view_origin.x * 0.58 + UV.x * view_size.x,
			view_origin.y * 0.86 + UV.y * view_size.y);
	float voids = deep_fbm(mid * 0.0021 + vec2(19.0, 5.0), 3);
	wall = mix(wall, zone_tint * 0.09, smoothstep(0.52, 0.78, voids));

	// Hanging stalactites along the top of the mid layer.
	float col_x = mid.x * 0.013;
	float tooth = deep_vnoise(vec2(floor(col_x), 4.0));
	float tooth_len = 60.0 + tooth * 190.0;
	float band_top = surface_y + 220.0 + deep_fbm(mid * 0.0015, 2) * 400.0;
	float taper = 1.0 - clamp((mid.y - band_top) / max(tooth_len, 1.0), 0.0, 1.0);
	float across = abs(fract(col_x) - 0.5) * 2.0;
	float spike = step(across, taper * 0.85) * step(band_top, mid.y);
	wall = mix(wall, zone_tint * 0.05, spike * 0.9);

	// Faint distant crystal seams: tiny warm/cool glints in the far wall.
	float seam = pow(deep_vnoise(far * 0.045 + vec2(13.0, 29.0)), 9.0);
	wall += vec3(0.30, 0.62, 0.78) * seam * 0.9;

	// Deep floor darkening — the bottom of the world is simply unlit.
	float floor_fade = clamp((wp.y - (world_bottom_y - 2600.0)) / 2600.0, 0.0, 1.0);
	wall *= 1.0 - floor_fade * 0.75;

	// ----------------------------------------------------------- composite ---
	col = mix(sky, wall, smoothstep(0.0, 1.0, underground));
	// The backdrop is distant, so it only receives ambient, never point lights.
	col *= mix(vec3(1.0), ambient_light, 0.72);

	COLOR = vec4(col, 1.0);
}
