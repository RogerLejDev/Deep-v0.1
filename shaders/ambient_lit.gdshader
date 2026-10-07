shader_type canvas_item;
render_mode unshaded, blend_mix;

// Used by every sprite that lives in the world (player, creatures, props) so
// they receive exactly the same ambient + point lighting as the terrain.

#include "res://shaders/lighting.gdshaderinc"

// Self-illumination, e.g. a Glowling's body or a torch flame.
uniform vec3 emission_colour : source_color = vec3(0.0);
uniform float emission_strength = 0.0;
// Flat tint multiplied into the texture, used for creature variants.
uniform vec4 tint : source_color = vec4(1.0);
// 0 = normal, 1 = pure silhouette (unidentified creature).
uniform float silhouette = 0.0;
uniform vec3 silhouette_colour : source_color = vec3(0.04, 0.05, 0.08);
// White flash on damage.
uniform float flash = 0.0;
// Fades the sprite out, used when a Phantom dissolves.
uniform float dissolve = 0.0;
// Vertical squash/stretch pivoted on the sprite's feet, driven by code for
// procedural animation without an authored spritesheet.
uniform vec2 squash = vec2(1.0, 1.0);
// Floor under the global ambient, per sprite.
//
// Terrain is allowed to go fully black — that is the point of being deep. A
// creature at zero light would be invisible rather than mysterious, so every
// sprite keeps a little self-visibility: a faint silhouette you notice and
// then have to light up to identify. The player keeps a much higher floor,
// because losing your own avatar in the dark is not tension, it is a bug.
uniform float ambient_floor = 0.09;

varying vec2 deep_world_pos;

void vertex() {
	VERTEX *= squash;
	deep_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.003) {
		discard;
	}
	vec3 albedo = tex.rgb * tint.rgb;

	vec3 ambient = max(deep_ambient, vec3(ambient_floor));
	vec3 lit = albedo * (ambient + deep_gather_light(deep_world_pos));
	lit += emission_colour * emission_strength;
	lit = mix(lit, silhouette_colour, silhouette);
	lit = mix(lit, vec3(1.0), flash);

	float a = tex.a * tint.a * (1.0 - dissolve);
	COLOR = vec4(lit, a);
}
