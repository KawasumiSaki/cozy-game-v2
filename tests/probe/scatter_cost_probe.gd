extends SceneTree
## MEASUREMENT, NOT AN ASSERTION.
##
##     godot --headless --path <repo> --script res://tests/probe/scatter_cost_probe.gd
##
## ---------------------------------------------------------------------------
## Where does a scatter rebuild's 142 ms of SAMPLING actually go?
##
## The field is 64 x 64 m and the candidate lattice is one point per square
## metre: 4096 points, and `scatter rebuild cost` says sampling is ~142 ms of the
## 146 ms total. That is 35 microseconds a point, which is a lot for "what is the
## ground here and what grows on it".
##
## The number matters because it is the wall between us and a LAWN. Grass is at
## 0.42 tufts per square metre and a field of grass is 10 to 30; the obvious fix
## is a finer lattice, and a lattice is quadratic — halving the step quadruples
## the candidates. So before choosing a way to get denser, find out what a
## candidate costs and which part of it dominates.
##
## Each piece is timed over the same 4096 points, in the same order the rebuild
## uses.
const PREFIX := "[probe]"
const SIDE := 64
const STEP := 1.0


func _initialize() -> void:
	var sys := CozyTerrainSystem.new()
	sys.setup(64.0, 64.0, Vector2(-28.0, -29.0))

	var count := 0
	var pts: Array[Vector2] = []
	var x := 0.0
	while x < 64.0 - 28.0:
		var z := 0.0
		while z < 64.0 - 29.0:
			pts.append(Vector2(x, z))
			z += STEP
		x += STEP
	count = pts.size()

	print("%s %d candidate(s) over a %d x %d m field" % [PREFIX, count, SIDE, SIDE])

	# 1. The material of the ground under a point.
	var t := Time.get_ticks_usec()
	var sink := 0
	for p in pts:
		sink += sys.material_id_at(p.x, p.y).length()
	_report("material_id_at", Time.get_ticks_usec() - t, count)

	# 1b. The height. It used to be read once per CANDIDATE and is now read once
	#     per PLANT, because a jittered plant is not standing where its square's
	#     own sample was taken. That is a correctness fix with a price, and the
	#     price is what decides whether density can go further.
	t = Time.get_ticks_usec()
	for p in pts:
		sink += int(sys.height_at(p.x + 0.3, p.y - 0.2) * 1000.0)
	_report("height_at", Time.get_ticks_usec() - t, count)

	# 1c. And the seed arithmetic a cluster costs: three draws plus the roll that
	#     decides how many. No terrain involved.
	t = Time.get_ticks_usec()
	for p in pts:
		var sv := int(p.x) * 31 + int(p.y)
		var k := CozyArtSeed.pick_index(sv ^ 0x2545f491, 9)
		for i in 10:
			var s := sv ^ (i * 0x9e3779b9)
			sink += int(CozyArtSeed.range_f(s ^ 0x1b873593, -0.45, 0.45) * 1000.0)
			sink += int(CozyArtSeed.range_f(s ^ 0xcc9e2d51, -0.45, 0.45) * 1000.0)
			sink += int(CozyArtSeed.range_f(s ^ 0x5bf03635, 0.7, 1.3) * 1000.0)
	_report("cluster seeds for 10 plants", Time.get_ticks_usec() - t, count)

	# 2. The biome — which is the only piece that looks at anything but the point.
	t = Time.get_ticks_usec()
	for p in pts:
		sink += CozyBiome.classify(sys, [], p.x, p.y, 20260911, false).length()
	_report("CozyBiome.classify (no water)", Time.get_ticks_usec() - t, count)

	# 2b. And the woodland half of it on its own: `classify` returns early on
	#     water/stone/sand, so on a grass field the region field is what actually
	#     runs.
	t = Time.get_ticks_usec()
	for p in pts:
		sink += 1 if CozyBiome.is_woodland(p.x, p.y, 20260911) else 0
	_report("  ...of which is_woodland", Time.get_ticks_usec() - t, count)

	# 3. The rule seed. `for_cell` takes the rule as a STRING and hashes it, and
	#    it is called once per rule per candidate.
	var rules := CozyScatterRule.ids()
	print("%s %d rule(s): %s" % [PREFIX, rules.size(), ", ".join(rules)])
	t = Time.get_ticks_usec()
	for p in pts:
		for r in rules:
			sink += CozyArtSeed.for_cell(20260911, Vector2i(0, 0), int(p.x), int(p.y), String(r))
	_report("for_cell x %d rule(s)" % rules.size(), Time.get_ticks_usec() - t, count)

	# 4. And the rest of the per-rule work: the probability tables.
	t = Time.get_ticks_usec()
	for p in pts:
		for r in rules:
			var res := CozyScatterRule.resolve(String(r))
			sink += 1 if CozyScatterRule.spawns_resolved(res, CozyBiome.GRASSLAND,
				"grass", false, int(p.x) + int(p.y)) else 0
	_report("resolve + spawns_resolved x %d" % rules.size(), Time.get_ticks_usec() - t, count)

	print("%s (sink %d, so nothing above is optimised away)" % [PREFIX, sink])
	sys.free()
	quit(0)


func _report(label: String, us: int, count: int) -> void:
	var per := float(us) / float(maxi(count, 1))
	print("%s %-34s %8.1f ms   (%6.2f us/candidate, %.0f%% of a 142 ms budget)" % [
		PREFIX, label, float(us) / 1000.0, per, per * 100.0 / 34.7])
