shader_type canvas_item;
render_mode unshaded, blend_mix;

// Full-screen depth haze. Thickens with depth, thins near light sources so a
// torch or a crystal seam visibly "cuts through" the murk, and carries a slow
// drift so the air feels like it is moving.

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/lighting.gdshaderinc"

uniform vec4 haze_colour : source_color = vec4(0.07, 0.09, 0.14, 0.25);
// World-space rect currently on screen, so the haze pattern is anchored to
// the world and does not swim when the camera moves.
uniform vec2 view_origin = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float drift = 0.0;

void fragment() {
	vec2 world_pos = view_origin + UV * view_size;

	float n = deep_fbm(world_pos * 0.0028 + vec2(drift * 0.05, drift * 0.013), 3);
	float n2 = deep_fbm(world_pos * 0.0071 - vec2(drift * 0.02, 0.0), 2);
	float density = mix(0.72, 1.28, n * 0.65 + n2 * 0.35);

	// Light burns the haze away locally; this is what gives lamps a visible
	// glow volume instead of a flat disc.
	vec3 l = deep_gather_light(world_pos);
	float burn = clamp(dot(l, vec3(0.333)) * 1.35, 0.0, 1.0);

	float a = haze_colour.a * density * (1.0 - burn * 0.85);
	// Scatter tints the haze towards whatever light is nearby.
	vec3 c = haze_colour.rgb + l * 0.18;
	COLOR = vec4(c, clamp(a, 0.0, 0.96));
}
