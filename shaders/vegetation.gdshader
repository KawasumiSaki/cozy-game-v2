shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Vegetation billboards that move: grass, flowers, trees, rocks.
//
// ---------------------------------------------------------------------------
// WHY THIS REPLACED `StandardMaterial3D.BILLBOARD_FIXED_Y`.
//
// The built-in billboard material does the facing and nothing else. Every plant
// in the world is a still image, and a field of still images reads as a diorama
// rather than as a place. What the reference project
// (DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo, MIT — see docs/CREDITS.md) does
// is move the QUAD rather than animate the sprite: the vertex shader bends each
// blade, so the picture never changes and the field still breathes.
//
// Three things are taken from it, and they are the three that carry the look:
//
//   1. WIND AS A WORLD-SPACE NOISE FIELD, not as a per-blade sine. The angle
//      comes from sampling a scrolling noise texture at the blade's own world
//      XZ, so a gust is a PLACE THAT MOVES across the field rather than every
//      blade separately deciding to wiggle. Two samples along slightly diverging
//      directions are multiplied, which is what stops the field from reading as
//      one texture sliding past.
//   2. A QUANTISED ANIMATION RATE. The bend is evaluated at `framerate` steps a
//      second instead of every frame, with a per-blade phase so the field does
//      not tick in unison. Smooth motion on a pixel-art sprite is most of what
//      makes it look wrong; stepping it is most of the style.
//   3. THE PIVOT IS THE BASE. A quad is centred on its own origin and ours are
//      lifted by half their height by the scatter, so rotating one as-is spins
//      it about its middle and the roots swing out of the ground.
//
// ---------------------------------------------------------------------------
// WHAT IS DELIBERATELY NOT HERE: LIGHTING.
//
// The reference project also shades its grass with a toon ramp and world-space
// cloud shadows, and copying that would make vegetation respond to the day/night
// cycle. It is not in this file because it changes how every plant LOOKS, while
// this file changes how it MOVES — and landing both at once means that if the
// result is wrong there is no way to tell which half caused it.
//
// NOTE FOR WHOEVER ADDS IT: vegetation is currently UNSHADED, and
// `main.gd._light_the_world()` only calls `set_light_level` on `objects` —
// plants are not in that list. Turning lighting on here ALONE makes the grass
// darken at night while the trees beside it do not.
//
// ---------------------------------------------------------------------------
// ART_PROFILE: this is a FIXED-Y billboard. The camera is locked (yaw 180,
// pitch 40) and the profile says sprites stay straight-on with the engine
// supplying the tilt — so the facing frame is built from the camera's horizontal
// right vector and world up, and never pitches with the camera.

// ---------------------------------------------------------------- the sprite

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

// Half the sprite's height in metres. The scatter lifts each quad by exactly
// this much times the instance scale, so the two have to agree — this is where
// the plant meets the ground, and everything rotates about it.
uniform float quad_half_height = 0.275;

// ---------------------------------------------------------------- the wind

// Scrolling noise, sampled in world space. Generated in GDScript
// (`CozyPixelArt`) rather than shipped as a file, which keeps the licence
// record short.
uniform sampler2D wind_noise : repeat_enable, filter_linear;
uniform vec2 wind_direction = vec2(0.0, 1.0);
uniform float wind_scale = 0.071;
uniform float wind_speed = 0.025;
uniform float wind_threshold : hint_range(-1.0, 1.0) = 0.365;
uniform float wind_angle : hint_range(0.0, 90.0) = 30.0;
uniform float noise_diverge_angle : hint_range(0.0, 45.0) = 10.0;

// ---------------------------------------------------------------- the rate

uniform float framerate = 5.0;
uniform bool quantised = true;

// ---------------------------------------------------------------- the variety

// How much taller or shorter one plant may be than its neighbours, and how far
// it may lean at rest. Both are per-INSTANCE, so two plants of the same kind are
// two plants rather than one stamped twice.
uniform float height_variety : hint_range(0.0, 1.0) = 0.35;
uniform float lean_variety : hint_range(0.0, 45.0) = 14.0;

// How much THIS kind of plant moves. A rock is drawn by the same shader as the
// grass and must not sway — a rock that bends reads as a bug rather than as
// wind, and a second shader for the one asset that stands still would be a
// second thing to keep in step.
uniform float wind_strength : hint_range(0.0, 2.0) = 1.0;


float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}


vec2 rotate2(vec2 v, float degrees) {
	float a = radians(degrees);
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}


// Rodrigues' rotation, in the compact form. Written as a matrix it is three
// rows that are easy to transpose by accident, and a transposed rotation is the
// same rotation backwards — a bug that reads as "the wind blows the wrong way".
vec3 rotate_about(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}


void vertex() {
	// The instance's own origin: the CENTRE of the quad, already lifted off the
	// ground by the scatter.
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Uniform scale, read off the basis rather than passed in a second time.
	float instance_scale = length(MODEL_MATRIX[0].xyz);
	float half_h = quad_half_height * instance_scale;

	float id = float(INSTANCE_ID);
	float seed = hash1(id);
	float seed_b = hash1(id + 7.0);

	// ---- the plant's own frame, fixed-Y --------------------------------------
	// Right is the camera's right flattened onto the ground plane; up is world
	// up. Nothing here pitches with the camera.
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 base = origin - up * half_h;

	// ---- where on the plant this vertex is -----------------------------------
	// Local y is centred on the quad, so `+ quad_half_height` puts the origin at
	// the base and this becomes the distance up the stem, in metres.
	float lx = VERTEX.x * instance_scale;
	float height_factor = 1.0 + height_variety * (seed - 0.5) * 2.0;
	float ly = (VERTEX.y + quad_half_height) * instance_scale * height_factor;

	// ---- the wind, sampled where this plant stands ---------------------------
	float frametime = 1.0 / max(framerate, 0.001);
	float time = TIME;
	if (quantised) {
		// Each plant steps on its own phase. A field that ticks in unison reads
		// as a stutter rather than as wind.
		float phase = mod(seed * 13.0, frametime);
		time = round((time + phase) * framerate) / framerate;
	}

	vec2 dir_a = normalize(rotate2(wind_direction, noise_diverge_angle));
	vec2 dir_b = normalize(rotate2(wind_direction, -noise_diverge_angle));
	float n1 = texture(wind_noise, origin.xz * wind_scale + time * wind_speed * dir_a).r;
	// The second sample runs at a different scale AND a different speed, so the
	// two do not line up into one visible texture.
	float n2 = texture(wind_noise, origin.xz * (wind_scale * 0.8)
		+ time * wind_speed * 0.89 * dir_b).r;
	float gust = clamp(n1 * n2 + wind_threshold, 0.0, 1.0);
	gust = (gust - 0.5) * 2.0;

	// ---- the bend ------------------------------------------------------------
	// Rotate the stem's up-axis toward the wind, about the axis perpendicular to
	// both. Bending TOWARD the wind rather than about the camera is what makes a
	// gust travel in a direction you can see.
	vec3 wind = normalize(vec3(wind_direction.x, 0.0, wind_direction.y));
	vec3 bend_axis = cross(up, wind);
	float bend = gust * radians(wind_angle);
	// At rest each plant leans a little of its own accord, so a still field is
	// not a row of identical verticals.
	bend += radians(lean_variety) * (seed_b - 0.5) * 2.0;
	bend *= wind_strength;

	vec3 stem_up = up;
	if (length(bend_axis) > 0.0001) {
		stem_up = rotate_about(up, normalize(bend_axis), bend);
	}

	// ---- the vertex ----------------------------------------------------------
	// In WORLD space, with the model matrix neutralised below, so nothing is
	// applied twice. The plant is a rigid quad swung about its base: the width
	// axis stays horizontal and only the stem direction leans.
	vec3 world = base + right * lx + stem_up * ly;
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = world;
}


void fragment() {
	vec4 c = texture(albedo_texture, UV);
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
