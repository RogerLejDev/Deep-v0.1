shader_type canvas_item;
render_mode unshaded, blend_mix;

// Terrain renderer for one chunk.
//
// Input is two tiny textures, (CHUNK+2)² each, carrying a one-tile border from
// the neighbouring chunks so edges and lighting are seamless:
//   tex_colour : rgb = per-tile base albedo (jittered on the CPU, but only in
//                      value, so a wall stays one material)
//                a   = solidity (0 or 1)
//   tex_extra  : rgb = emission colour premultiplied by strength
//                a   = packed: floor(a*255/64) = flags (1 organic, 2 crystal),
//                      fract(a*255/64) = per-tile random seed
//
// The silhouette comes from bilinearly filtering the solidity channel and
// thresholding it with a steep contrast curve: straight walls land exactly on
// the tile boundary (so collision matches what you see), convex corners get a
// small bevel, and a world-space noise term frays the rim so nothing reads as
// a clean grid. Inside the silhouette, each tile still gets a seam and a lit
// top face — this is a mining game, and the player has to be able to see what
// one block is.

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/lighting.gdshaderinc"

uniform sampler2D tex_colour : filter_linear, repeat_disable;
uniform sampler2D tex_extra : filter_linear, repeat_disable;

uniform vec2 chunk_origin = vec2(0.0);
uniform float tiles = 32.0;
uniform float tile_px = 16.0;
// 0 near the surface, 1 at the bottom of the world. Drives grit and coldness.
uniform float depth_ratio = 0.0;
// How far the rim may wander from the tile boundary, in tile fractions.
uniform float edge_fray = 0.10;
// Higher = squarer corners. 1.0 would be fully rounded blobs.
uniform float edge_contrast = 2.1;
uniform vec3 rim_tint : source_color = vec3(1.0, 0.95, 0.84);

const float PAD = 1.0;

vec2 padded_uv(vec2 uv) {
	return (uv * tiles + PAD) / (tiles + 2.0 * PAD);
}

vec2 tile_centre_uv(vec2 uv) {
	return (floor(uv * tiles) + 0.5 + PAD) / (tiles + 2.0 * PAD);
}

float solidity(vec2 uv) {
	return texture(tex_colour, padded_uv(uv)).a;
}

// Solidity of the tile `offset` tiles away, sampled exactly at its centre.
float neighbour(vec2 uv, vec2 offset) {
	vec2 c = (floor(uv * tiles) + offset + 0.5 + PAD) / (tiles + 2.0 * PAD);
	return texture(tex_colour, c).a;
}

void fragment() {
	vec2 world_pos = chunk_origin + UV * tiles * tile_px;

	vec2 cuv = tile_centre_uv(UV);
	vec4 base = texture(tex_colour, cuv);
	vec4 extra = texture(tex_extra, cuv);

	float packed = extra.a * 255.0;
	float flags = floor(packed / 64.0);
	float tile_seed = fract(packed / 64.0);
	bool organic = mod(flags, 2.0) >= 1.0;
	bool crystalline = flags >= 2.0;

	// --- silhouette ----------------------------------------------------------
	float field = solidity(UV);
	// Steepen around the 0.5 crossing: keeps walls flush with the tile grid
	// and stops corners melting into circles.
	field = clamp((field - 0.5) * edge_contrast + 0.5, 0.0, 1.0);
	float fray = deep_fbm(world_pos * 0.09, 2) - 0.5;
	field += fray * edge_fray;
	float aa = max(fwidth(field), 0.004) * 1.1;
	float alpha = smoothstep(0.5 - aa, 0.5 + aa, field);
	if (alpha <= 0.002) {
		discard;
	}

	// --- surface detail ------------------------------------------------------
	vec3 albedo = base.rgb;

	float grain = deep_fbm(world_pos * 0.22, 3);
	float coarse = deep_fbm(world_pos * 0.055 + vec2(31.0, 7.0), 2);

	if (organic) {
		// Fibres running along the material rather than isotropic grain.
		float fibre = deep_ridged(world_pos * vec2(0.06, 0.34), 2);
		albedo *= mix(0.74, 1.30, fibre);
		albedo *= mix(0.90, 1.10, grain);
	} else if (crystalline) {
		// Large flat facets with hard value steps, plus a travelling glint.
		float facet = floor(deep_fbm(world_pos * 0.08, 2) * 5.0) / 5.0;
		albedo *= mix(0.60, 1.55, facet);
		float sparkle = pow(deep_vnoise(world_pos * 0.85 + vec2(deep_time * 0.3)), 16.0);
		albedo += vec3(sparkle) * 1.8;
	} else {
		// Rock: broad value blotches plus fine grit.
		albedo *= mix(0.66, 1.26, coarse);
		albedo *= mix(0.86, 1.14, grain);
	}

	// Mineral speckle, keyed off the per-tile seed so density varies tile to
	// tile instead of being a uniform dither.
	float speck = step(0.88 - tile_seed * 0.05, deep_vnoise(world_pos * 1.4));
	albedo += albedo * speck * 0.34;

	// Cracks: thin dark ridges, denser the deeper you go (compression).
	float crack = deep_ridged(world_pos * 0.10 + vec2(5.1, 2.3), 2);
	float crack_mask = smoothstep(0.78, 0.97, crack) * (0.40 + depth_ratio * 0.4);
	albedo *= 1.0 - crack_mask * 0.55;

	// --- per-tile form -------------------------------------------------------
	// This is what makes the terrain legible as breakable blocks.
	vec2 f = fract(UV * tiles);
	float s_up = neighbour(UV, vec2(0.0, -1.0));
	float s_down = neighbour(UV, vec2(0.0, 1.0));
	float s_left = neighbour(UV, vec2(-1.0, 0.0));
	float s_right = neighbour(UV, vec2(1.0, 0.0));

	// Seam: a soft dark line inside every tile border, but only against
	// another solid tile — the silhouette already handles open edges.
	float seam_x = (1.0 - smoothstep(0.0, 0.11, f.x)) * s_left
		+ (1.0 - smoothstep(0.0, 0.11, 1.0 - f.x)) * s_right;
	float seam_y = (1.0 - smoothstep(0.0, 0.11, f.y)) * s_up
		+ (1.0 - smoothstep(0.0, 0.11, 1.0 - f.y)) * s_down;
	float seam = clamp(max(seam_x, seam_y), 0.0, 1.0);
	// Wobble the seam with noise so the grid never reads as perfectly ruled.
	seam *= mix(0.55, 1.0, deep_vnoise(world_pos * 0.5));
	albedo *= mix(1.0, 0.80, seam);

	// Lit top face: the band at the top of a tile whose neighbour above is air.
	float top_band = 1.0 - smoothstep(0.0, 0.26, f.y);
	float exposed_top = top_band * (1.0 - s_up);
	albedo += albedo * rim_tint * exposed_top * mix(0.95, 0.30, depth_ratio);

	// A thin contact shadow under an overhang, so ceilings read as ceilings.
	float under_band = 1.0 - smoothstep(0.0, 0.3, 1.0 - f.y);
	albedo *= mix(1.0, 0.74, under_band * (1.0 - s_down));

	// Ambient occlusion deep inside a mass of rock.
	float interior = smoothstep(0.52, 1.0, field);
	albedo *= mix(1.0, 0.84, interior * 0.5);

	// --- lighting ------------------------------------------------------------
	vec3 lit = deep_light_albedo(albedo, world_pos);

	// Emissive materials light themselves and breathe slightly.
	vec3 emission = extra.rgb;
	float breathe = 0.82 + 0.18 * sin(deep_time * 1.7 + tile_seed * 24.0);
	lit += emission * breathe * (0.85 + 0.8 * (1.0 - interior));

	COLOR = vec4(lit, alpha);
}
