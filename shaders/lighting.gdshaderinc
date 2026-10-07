// DEEP's 2D lighting model.
//
// Rather than Light2D nodes, every lit shader samples one shared 16x2 RGBAF
// "light data" texture that the World refreshes each frame with the lights
// currently on screen. Reasons:
//   * terrain, creatures, props and background all receive *identical*
//     lighting, so nothing pops when it crosses a light boundary;
//   * ambient darkness can multiply the albedo without also dimming the
//     lights, which is what happens with CanvasModulate;
//   * these are `global uniform`s, so the World writes them once per frame
//     instead of once per material per frame;
//   * it is one texture fetch pair per light per fragment, with a hard cap,
//     which keeps the cost predictable on mobile GPUs.
//
// Layout, column i of DEEP_MAX_LIGHTS:
//   row 0: xy = world position (px), z = radius (px), w = intensity
//   row 1: rgb = colour, a = flicker phase

const int DEEP_MAX_LIGHTS = 16;

global uniform sampler2D deep_light_data : filter_nearest, repeat_disable;
global uniform int deep_light_count;
global uniform vec3 deep_ambient;
global uniform float deep_time;

vec3 deep_gather_light(vec2 world_pos) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < DEEP_MAX_LIGHTS; i++) {
		if (i >= deep_light_count) break;
		float u = (float(i) + 0.5) / float(DEEP_MAX_LIGHTS);
		vec4 p = texture(deep_light_data, vec2(u, 0.25));
		if (p.z <= 0.5) continue;
		vec4 c = texture(deep_light_data, vec2(u, 0.75));
		float d = length(world_pos - p.xy);
		// Soft quadratic falloff; flicker rides on the intensity only so the
		// light's reach stays stable and the wobble reads as a flame rather
		// than a pulsing sphere.
		float att = 1.0 - smoothstep(0.0, p.z, d);
		att *= att;
		float flicker = 1.0 + sin(deep_time * 11.0 + c.a * 6.283) * 0.07
			+ sin(deep_time * 23.0 + c.a * 12.9) * 0.04;
		acc += c.rgb * att * p.w * flicker;
	}
	return acc;
}

// Combined ambient + dynamic lighting for an albedo sample.
vec3 deep_light_albedo(vec3 albedo, vec2 world_pos) {
	return albedo * (deep_ambient + deep_gather_light(world_pos));
}
