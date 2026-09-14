shader_type spatial;
render_mode cull_back, specular_disabled;

// The ground: dual-grid tiles, decided per fragment, textured with a repeating
// material texture.
//
// ---------------------------------------------------------------------------
// WHY A SHADER AND NOT GEOMETRY.
//
// The same rule bakes into a mesh — one quad per display tile, sixteen per
// material in an atlas — and that is what this replaced. It works, and it is the
// shape both reference projects use, because they ARE tilemaps: a `TileMapLayer`
// holds one cell per tile and the tile is an image.
//
// Here it costs 4096 quads per chunk and the texture in each is a 16-texel
// picture that cannot repeat, because a picture OF a tile is not a texture of
// the ground. Per fragment it costs ONE quad for the whole chunk, the tile is
// decided from four texel fetches, and the material's texture is sampled with
// `repeat_enable` so it flows across tile boundaries the way a ground texture
// should.
//
// What is unchanged is the technique: a display grid offset half a cell from the
// cell grid, so every display tile sits where four cells meet and looks at FOUR
// neighbours rather than eight.
//
// ---------------------------------------------------------------------------
// THE MESH DOES NOT MOVE. The chunk's collider is a flat box decided elsewhere,
// so nothing here can put the picture and the collision out of step — a freedom
// the heightfield never had, and the reason `chunk_collision_min_y` existed.
// Do NOT add `VERTEX.y += ...`.

// One material texture per layer, in `CozyTerrainMaterials.ORDER`.
uniform sampler2DArray materials : source_color, filter_nearest, repeat_enable;

// One texel per cell: R is the material INDEX, G is the cell's grain.
//
// NEVER FILTERED, ALWAYS FETCHED BY INTEGER COORDINATE. An index is a name, and
// averaging two names picks a third that nobody asked for.
uniform sampler2D control : filter_nearest, repeat_disable;

// How many materials the table holds. Comes from GDScript rather than from a
// constant in here, so the assertion can compare it with the material table — a
// count that lives only inside a shader is a count this side cannot check.
uniform int material_count = 6;

// The chunk is a square of this many metres, and the mesh spans it exactly.
uniform float chunk_metres = 16.0;

// A cell is this many metres. The terrain's own simulation unit.
uniform float cell_metres = 0.25;

// One material texture covers this many metres before repeating.
uniform float texture_metres = 1.0;

// Multiplied into the albedo from the control texture's green channel. Narrow on
// purpose: this is what stops a large field reading as flat paint.
uniform float grain = 0.09;

varying vec3 chunk_local;

// The four quadrants of a display tile, in the order the mask bits mean them.
const int QUAD_TL = 1;
const int QUAD_TR = 2;
const int QUAD_BL = 4;
const int QUAD_BR = 8;

// A hard cap so the loop has a constant bound; `material_count` gates it.
const int MAX_MATERIALS = 16;


int index_at(ivec2 c, ivec2 limit) {
	return int(texelFetch(control, clamp(c, ivec2(0), limit), 0).r * 255.0 + 0.5);
}


void vertex() {
	chunk_local = VERTEX;
}


void fragment() {
	vec2 uv = chunk_local.xz / chunk_metres + vec2(0.5);
	float cells = chunk_metres / cell_metres;
	ivec2 limit = ivec2(int(cells) - 1);

	vec2 cell_pos = uv * cells;
	ivec2 cell = ivec2(clamp(floor(cell_pos), vec2(0.0), vec2(cells - 1.0)));
	vec2 local = fract(cell_pos);

	// The DUAL GRID: the nearest CORNER of this cell, and the four cells that
	// meet there. One display tile per corner, so a tile has four neighbours to
	// look at and never eight — which is the whole of the technique.
	ivec2 corner = cell + ivec2(local.x > 0.5 ? 1 : 0, local.y > 0.5 ? 1 : 0);
	ivec2 base = corner - ivec2(1, 1);

	int q0 = index_at(base, limit);                       // top-left
	int q1 = index_at(base + ivec2(1, 0), limit);         // top-right
	int q2 = index_at(base + ivec2(0, 1), limit);         // bottom-left
	int q3 = index_at(base + ivec2(1, 1), limit);         // bottom-right

	// WHICH QUADRANT OF THE DISPLAY TILE THIS FRAGMENT IS IN — a fact about the
	// cell it is standing in, relative to the corner.
	ivec2 rel = cell - base;
	int bit = QUAD_TL << (rel.y * 2 + rel.x);

	// -------------------------------------------------------------------
	// THE LAYERS, lowest material index first, so the LAST one to claim the
	// fragment wins — the order a mesh would have drawn them in, without a mesh.
	//
	// A material claims a fragment when it is present in the quadrant the
	// fragment occupies. That is the corner rule: near a corner a fragment can be
	// standing in a cell whose material is NOT what a higher-priority neighbour
	// puts there, and the neighbour takes it — which is what curves the boundary
	// instead of stepping around it.
	int chosen = -1;
	for (int m = 0; m < MAX_MATERIALS; m++) {
		if (m >= material_count) {
			break;
		}
		int mask = 0;
		if (q0 == m) { mask |= QUAD_TL; }
		if (q1 == m) { mask |= QUAD_TR; }
		if (q2 == m) { mask |= QUAD_BL; }
		if (q3 == m) { mask |= QUAD_BR; }
		if (mask != 0 && (mask & bit) != 0) {
			chosen = m;
		}
	}

	// A fragment no layer claimed would be a hole in the ground. It cannot happen
	// — the fragment's own cell always has a material and that material is always
	// present in its own quadrant — but a hole is worth a fallback rather than a
	// gamble, and a magenta one is visible rather than subtle.
	vec4 own = texelFetch(control, cell, 0);
	if (chosen < 0) {
		chosen = int(own.r * 255.0 + 0.5);
	}

	// CONTINUOUS ACROSS THE WHOLE CHUNK, not restarted per tile: the texture
	// flows over the ground and only the material changes underneath it. A
	// texture restarted at every tile edge would show that edge, because the
	// sampler has nothing to wrap against.
	vec2 tex_uv = uv * (chunk_metres / texture_metres);
	vec3 ground = texture(materials, vec3(tex_uv, float(chosen))).rgb;

	float shade = mix(1.0 - grain, 1.0 + grain, own.g);
	ALBEDO = ground * shade;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
