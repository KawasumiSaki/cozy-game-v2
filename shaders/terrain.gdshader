shader_type spatial;
render_mode cull_back, specular_disabled;

// The ground: one material per cell, picked from a control texture, drawn with a
// repeating pixel texture out of an array.
//
// ---------------------------------------------------------------------------
// THE MESH DOES NOT MOVE, AND THE COLLISION IS BUILT FROM IT.
//
// `CozyTerrainRenderer._rebuild_chunk` makes the trimesh shape from the very
// same `ArrayMesh` this shades, and `chunk_collision_min_y` exists to catch the
// two drifting apart. So: NO `VERTEX.y +=` here, ever. A shader that displaces
// the surface would move the picture and leave the collider behind, and on flat
// ground nothing would show until someone dug.
//
// ---------------------------------------------------------------------------
// WHY AN ARRAY AND NOT AN ATLAS. A sub-region of an atlas cannot use hardware
// repeat, so everyone ends up doing `mod(UV, 1.0)` by hand — and then the
// sampler pulls in the neighbouring cell's texels at the region edge, which is
// the classic bleed. `Texture2DArray` layers are independent, so the problem
// does not exist, and `repeat_enable` is honoured on the array sampler where it
// is silently ignored on an array of `sampler2D`.
//
// ---------------------------------------------------------------------------
// THE INDEX IS NEVER INTERPOLATED. A material id is a NAME, not a number to
// average: interpolate it and a fragment halfway between grass and stone picks a
// third material nobody chose. So it is fetched with `texelFetch` from a texture
// rather than carried in a varying — `varying flat` would avoid the averaging
// but is constant per TRIANGLE, and every cell here is two triangles, so it
// would put a diagonal seam through the middle of each cell.

// The materials, one layer each, in `CozyTerrainMaterials.ORDER`.
uniform sampler2DArray materials : source_color, filter_nearest, repeat_enable;

// One texel per cell: R is the material index, G is the cell's deterministic
// grain. Never sampled with a filter — it is read by integer coordinate.
uniform sampler2D control : filter_nearest, repeat_disable;

// The chunk is a square of this many metres, and the mesh spans it exactly.
uniform float chunk_metres = 16.0;

// One material texture covers this many metres before repeating. At 16 texels
// and one metre that is ~6 cm per texel, which is the same order as the
// project's own pixel density — the ground reads as texture rather than paint,
// without turning into noise at the locked camera distance.
uniform float texture_metres = 1.0;

// Dual tiling: the material decided at the corners where four cells meet,
// rather than inside each cell. 1 is on, 0 is the plain per-cell read.
uniform float dual_tile = 1.0;

// Multiplied into the albedo, from the control texture's G channel. Narrow on
// purpose: this is what stops a large field reading as flat paint.
uniform float grain = 0.09;

varying vec3 chunk_local;

void vertex() {
	// Model space, and the mesh is built centred on the chunk's origin, so this
	// is a cell coordinate already.
	chunk_local = VERTEX;
}

void fragment() {
	// 0..1 across the chunk.
	vec2 uv = chunk_local.xz / chunk_metres + vec2(0.5);

	// Which cell this fragment is in, clamped so the top and right edges of the
	// chunk read their own cell rather than a texel that is not there.
	float cells = chunk_metres / 0.25;
	vec2 cell_pos = uv * cells;
	vec2 local = fract(cell_pos);
	ivec2 cell = ivec2(clamp(floor(cell_pos), vec2(0.0), vec2(cells - 1.0)));
	vec4 ctl = texelFetch(control, cell, 0);

	int layer = int(ctl.r * 255.0 + 0.5);

	// -------------------------------------------------------------------
	// DUAL-TILE: the material is decided at the CORNERS, not inside the cell.
	//
	// A cell's material is authored per cell. Read straight, that puts every
	// boundary on a cell edge and every corner at a right angle, which is what a
	// grid looks like. Dual tiling moves the decision to the corner where four
	// cells meet: the four of them are read, and the one with the highest
	// priority wins the whole neighbourhood around that corner.
	//
	// The effect is that a higher-priority material grows outward into the
	// corners of the cells beside it. Its region comes out rounded rather than
	// squared off, and a boundary between two materials turns through the corner
	// instead of stepping around it -- which is the look dual-grid tilemaps are
	// used for.
	//
	// IT COSTS FOUR EXTRA TEXEL FETCHES AND MOVES NOTHING. The mesh, the
	// triangles and the trimesh collision are exactly as they were: this decides
	// which pixel gets which colour and nothing else. What it DOES move is the
	// apparent position of a boundary -- by up to half a cell, 12.5 cm -- so a
	// dug cell's edge shows a little off from the cell that was dug. `dual_tile`
	// at 0 turns it off.
	if (dual_tile > 0.5) {
		// The cell corner nearest this fragment.
		ivec2 corner = cell + ivec2(local.x > 0.5 ? 1 : 0, local.y > 0.5 ? 1 : 0);
		int best = layer;
		for (int dz = -1; dz <= 0; dz++) {
			for (int dx = -1; dx <= 0; dx++) {
				ivec2 c = clamp(corner + ivec2(dx, dz),
					ivec2(0), ivec2(int(cells) - 1));
				best = max(best, int(texelFetch(control, c, 0).r * 255.0 + 0.5));
			}
		}
		layer = best;
	}

	// CONTINUOUS ACROSS THE WHOLE CHUNK, not restarted per cell: the texture
	// flows over the ground and only the material changes underneath it. A
	// texture restarted at every cell edge would show that edge, because the
	// sampler has nothing to wrap.
	vec2 tex_uv = uv * (chunk_metres / texture_metres);
	vec3 ground = texture(materials, vec3(tex_uv, float(layer))).rgb;

	// The control texture's green channel, widened back out to a multiplier.
	float shade = mix(1.0 - grain, 1.0 + grain, ctl.g);

	ALBEDO = ground * shade;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
