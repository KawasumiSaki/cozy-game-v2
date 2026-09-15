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

// A SILHOUETTE, NOT A PICTURE. The reference project's sprites are pure white
// with an alpha cut — every pixel that is drawn is (255,255,255) — and the
// COLOUR COMES FROM HERE. That is the trick that makes a field of one sprite
// read as a landscape: the shape is drawn once, and the shader decides what
// colour this patch of ground is.
//
// It also means a coloured sprite would be a bug rather than a variation: the
// shader multiplies the texture by these colours, so anything not white would
// tint the result twice.
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

// IS THIS SPRITE A SILHOUETTE, or a picture that carries its own colours?
//
// Grass and the accent tufts are silhouettes: white, one colour for the whole
// plant, and the shader decides which colour. A TREE is not — it has a brown
// trunk and a green canopy, and no single tint can produce both. So a painted
// sprite keeps its own colours, skips the patches, and keeps the outline that
// `CozyPixelArt` already baked into it.
//
// One shader for the whole layer, and this is the one bit that differs between
// the two kinds of plant. The alternative was two shaders with the wind code
// copied into both, which is the thing that drifts.
uniform bool silhouette = true;

// The base colour, and the darker outline this project draws around every
// sprite so it stays readable against the ground (`CozyPixelArt._outline`).
// The outline is done here rather than baked into the mask because the mask is
// not ours to redraw — see docs/CREDITS.md.
uniform vec4 tint : source_color = vec4(0.38, 0.60, 0.30, 1.0);
uniform vec4 outline_colour : source_color = vec4(0.16, 0.26, 0.14, 1.0);

// ---------------------------------------------------------------- the patches

// Two more greens, each selected where its own noise crosses a threshold.
//
// SAMPLED IN WORLD XZ, which is the whole point: the patches are properties of
// PLACES, so they do not swim when the camera moves and they line up across the
// boundary between two chunk meshes. The frequencies are deliberately tiny —
// the reference's scales are around 1/200 m — because these are meant to read as
// a hillside being slightly different from the next one, not as mottling. Small
// patches on a 0.55 m sprite would just be noise on a blade of grass.
uniform vec4 albedo2 : source_color = vec4(0.32, 0.53, 0.26, 1.0);
uniform sampler2D albedo2_noise : repeat_enable, filter_linear;
uniform float albedo2_scale = 0.005;
uniform float albedo2_threshold : hint_range(0.0, 1.0) = 0.604;

uniform vec4 albedo3 : source_color = vec4(0.45, 0.68, 0.33, 1.0);
uniform sampler2D albedo3_noise : repeat_enable, filter_linear;
uniform float albedo3_scale = 0.003;
uniform float albedo3_threshold : hint_range(0.0, 1.0) = 0.661;

// One texel, for the outline pass below.
uniform vec2 sprite_texel = vec2(0.0416667, 0.0416667);

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

// HOW FAR THIS PIECE OF A PLANT IS FROM THE PIECE BEHIND IT, in metres.
//
// A LAYERED TREE IS FOUR QUADS AT ONE POSITION, and the wind is sampled WHERE THE
// PLANT STANDS — so without this every layer of one tree reads the same gust and
// bends in perfect lockstep, which is the one thing a layered tree exists to
// avoid. The offset moves this piece's sample through the gust field, so the
// front leaves and the back leaves meet the same wind a moment apart.
//
// IT IS A DISTANCE, NOT A TIME, on purpose: two trees of the same kind then differ
// from each other for the ordinary reason (they stand in different places), and a
// layered one differs from itself for the same reason. Zero is everything that is
// not a layer, which is every other plant in the world.
uniform float layer_phase = 0.0;


// Where this plant stands, in world space, carried to the fragment. `VERTEX` is
// view space there, so the colour patches cannot be sampled from it.
varying vec3 world_pos;


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
	// PER-INSTANCE, and deliberately NOT shifted by `layer_phase`: every piece of
	// one plant scales together, or the leaves grow out of the trunk they belong
	// to. Instance ids line up across the pieces because the scatter fills every
	// piece's mesh from the same list in the same order.
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
	// WHERE THIS PIECE READS THE GUST FROM. Zero for everything that is not a layer
	// of a layered plant, so the ordinary field is unchanged.
	vec2 sample_at = origin.xz + vec2(layer_phase * 0.7, layer_phase * 0.5);
	float n1 = texture(wind_noise, sample_at * wind_scale + time * wind_speed * dir_a).r;
	// The second sample runs at a different scale AND a different speed, so the
	// two do not line up into one visible texture.
	float n2 = texture(wind_noise, sample_at * (wind_scale * 0.8)
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
	world_pos = world;
	MODELVIEW_MATRIX = VIEW_MATRIX;
	VERTEX = world;
}


// NO EARLY `return` IN THIS FUNCTION. Godot's shader language rejects it --
// "Using 'return' in the 'fragment' processor function is incorrect" -- and that
// is a COMPILE error, not a warning: the whole material falls back and every
// plant in the field stops moving. So the result is accumulated in locals and
// written once at the bottom.
void fragment() {
	vec4 c = texture(albedo_texture, UV);
	vec3 result_colour = c.rgb;
	float result_alpha = c.a;

	if (silhouette) {
		// `VERTEX` in a FRAGMENT shader is view space, whatever `vertex()` left
		// it as, so the world position is carried across in a varying rather than
		// recomputed here. Getting this wrong is invisible at the origin and
		// badly wrong at the camera.
		vec3 place = world_pos;

		vec4 colour = tint;
		if (texture(albedo2_noise, place.xz * albedo2_scale).r > albedo2_threshold) {
			colour = albedo2;
		}
		if (texture(albedo3_noise, place.xz * albedo3_scale).r > albedo3_threshold) {
			colour = albedo3;
		}
		result_colour = c.rgb * colour.rgb;

		// THE OUTLINE. This project draws a dark line around every sprite so it
		// stays readable against the ground, and the reference's masks have none.
		// Rather than redraw their art -- the one thing a CC BY licence does not
		// let us quietly do -- the line is grown here: a transparent texel with an
		// opaque neighbour becomes outline.
		//
		// One texel on a 24 px sprite is the same weight the baked outlines in
		// `CozyPixelArt` carry, so it sits with them. The sampler CLAMPS, so the
		// outermost texel of a sprite looks at itself -- which is why a silhouette
		// that touched the edge of its image would lose its outline there, and why
		// the sprites in `assets/art/pixel/environment` keep a pixel of padding.
		if (c.a < alpha_scissor) {
			float neighbour = max(
				max(texture(albedo_texture, UV + vec2(sprite_texel.x, 0.0)).a,
					texture(albedo_texture, UV - vec2(sprite_texel.x, 0.0)).a),
				max(texture(albedo_texture, UV + vec2(0.0, sprite_texel.y)).a,
					texture(albedo_texture, UV - vec2(0.0, sprite_texel.y)).a));
			if (neighbour >= alpha_scissor) {
				result_colour = outline_colour.rgb;
				result_alpha = 1.0;
			}
		}
	}

	ALBEDO = result_colour;
	ALPHA = result_alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
