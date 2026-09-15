extends SceneTree
## MEASUREMENT, NOT AN ASSERTION.
##
##     godot --headless --path <repo> --script res://tests/probe/chunk_flag_probe.gd
##
## ---------------------------------------------------------------------------
## Does a chunk's MATERIAL FLAG survive every way a material is allowed to change?
##
## `CozyTerrainChunk.has_water` exists so a scatter pass can skip the shore test
## in a world that holds no water. It is maintained inside `set_material`, which
## the project treats as the one funnel every cell change goes through.
##
## "There is one funnel" is a claim, not a fact. `ground_points.gd`'s header
## already lists the sites that change terrain without passing any funnel, and
## one of them writes the packed arrays DIRECTLY rather than through a setter:
## `CozyTerrainChunk.from_dict`, which assigns `_material` cell by cell.
##
## So ask the flag the question it exists to answer — has water / has no water —
## at every step of a material's life, including a save/load round trip, and ask
## the MATERIAL the same question alongside it. The pair is the whole point: if
## both go false the round trip simply lost the edit, which is a different bug
## with a different fix.
##
## A flag that is correct until a load and wrong after it is worse than no flag:
## the reader is a classification pass that quietly decides the world is dry, and
## nothing prints.
const PREFIX := "[probe]"

## World (2, 2) lands in the chunk at local cell (8, 8) at 0.25 m per cell. The
## setter takes world coordinates and the reader takes local ones, and reading
## (2, 2) back answers about a DIFFERENT cell — the first version of this probe
## did exactly that and printed "material=grass", which looked like data loss and
## was a coordinate mix-up.
const WORLD_X := 2.0
const WORLD_Z := 2.0
const LOCAL_X := 8
const LOCAL_Z := 8


func _initialize() -> void:
	var sys := CozyTerrainSystem.new()
	sys.setup(64.0, 64.0, Vector2.ZERO)

	var chunk: CozyTerrainChunk = sys.chunks[Vector2i(0, 0)]
	print("%s a fresh chunk:                       has_water=%s" % [
		PREFIX, str(chunk.has_water)])

	# 1. The path everyone knows about.
	sys.set_material_at(WORLD_X, WORLD_Z, "water")
	print("%s after set_material_at(2,2,'water'): has_water=%s  material=%s" % [
		PREFIX, str(chunk.has_water), chunk.material_id_at(LOCAL_X, LOCAL_Z)])

	# 2. The chunk's own serialiser, which is what a save file is made of.
	var chunk_back := CozyTerrainChunk.from_dict(chunk.to_dict())
	print("%s after chunk to_dict/from_dict:      has_water=%s  material=%s" % [
		PREFIX, str(chunk_back.has_water), chunk_back.material_id_at(LOCAL_X, LOCAL_Z)])

	# 3. The system's, which is the route `_check_scatter_incremental` takes on
	#    the LIVE terrain (main.gd:2798) and `_load_world` takes on every F9.
	var sys_back := CozyTerrainSystem.new()
	sys_back.from_dict(sys.to_dict())
	var b: CozyTerrainChunk = sys_back.chunks[Vector2i(0, 0)]
	print("%s after system to_dict/from_dict:     has_water=%s  material=%s" % [
		PREFIX, str(b.has_water), b.material_id_at(LOCAL_X, LOCAL_Z)])

	# 4. And edit the loaded chunk, so the flag is shown to be REACHABLE rather
	#    than merely stuck false: if this one reads false too, the edit path is
	#    broken as well and the round trip is not the only suspect.
	b.set_material(3, 3, "water")
	print("%s after an edit on the LOADED chunk:  has_water=%s" % [
		PREFIX, str(b.has_water)])

	print("%s ---- the same question asked of the material field ----" % PREFIX)
	print("%s live system:   %d water cell(s), of which (8,8)=%s" % [
		PREFIX, _count_water(sys), sys.material_id_at(WORLD_X, WORLD_Z)])
	print("%s loaded system: %d water cell(s), of which (8,8)=%s" % [
		PREFIX, _count_water(sys_back), sys_back.material_id_at(WORLD_X, WORLD_Z)])

	sys.free()
	sys_back.free()
	quit(0)


## Counted from the material field itself, not from any flag — this is the
## reference the flags are being compared against.
func _count_water(sys: CozyTerrainSystem) -> int:
	var n := 0
	for coord in sys.chunks:
		var c: CozyTerrainChunk = sys.chunks[coord]
		for lz in CozyTerrainChunk.CELLS:
			for lx in CozyTerrainChunk.CELLS:
				if c.material_id_at(lx, lz) == "water":
					n += 1
	return n
