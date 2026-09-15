class_name CozyMonster
extends CharacterBody3D
## Something in the world that can be killed, and that leaves something behind.
##
## ---------------------------------------------------------------------------
## WHY THIS IS THE PIECE THAT WAS MISSING
##
## Every part of the equipment lane was finished and unreachable. `CozyStats`
## resolves four passes; `CozyItemGenerator` rolls instances with rolled affixes;
## `CozyLootRoller` turns a table into drops; `CozyItemContainer` and
## `CozyEquipment` hold and wear them. NOTHING IN THE WORLD PRODUCED ONE. The
## player could not obtain an item, so no item could be equipped, so no number
## could move — and every test of every one of those systems passed.
##
## A monster is the source. It is the smallest one: it has health, it dies, and
## it rolls its table into whoever killed it.
##
## ---------------------------------------------------------------------------
## WHAT IT IS NOT
##
## IT DOES NOT FIGHT BACK. See `CozyMonsterDefs` for why that is a decision
## rather than an omission, and what row arrives with the driver that reads it.
##
## IT DOES NOT MOVE. Wandering needs navigation the player does not have, and a
## monster that walks into a wall is worse than one that stands still.

var def_id := ""
var hp := 0.0
var hp_max := 0.0

## Who last hit it. Kept so a death can pay the person who caused it rather than
## whoever happens to be standing nearby — with one player it is the same answer,
## and with two it is the difference between a kill and a theft.
var _last_attacker: Node = null

var _body: MeshInstance3D = null
var _bar: MeshInstance3D = null
var _bar_max_width := 0.0


func setup(p_def_id: String) -> void:
	def_id = p_def_id
	hp_max = CozyMonsterDefs.hp(def_id)
	hp = hp_max


func _ready() -> void:
	var def := CozyMonsterDefs.get_def(def_id)
	var size: Vector2 = def.get("size", Vector2(0.8, 0.8))
	var height := CozyMonsterDefs.height(def_id)

	var box := BoxMesh.new()
	box.size = Vector3(size.x, height, size.y)
	_body = MeshInstance3D.new()
	_body.mesh = box
	_body.position = Vector3(0.0, height * 0.5, 0.0)
	_body.material_override = CozyPixelArt.make_flat_material(
		def.get("colour", Color.WHITE))
	add_child(_body)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(size.x, size.y) * 0.5
	capsule.height = height
	shape.shape = capsule
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)

	# A health bar over its head, because a target with no visible health is a
	# target the player cannot tell is being hurt. It is a plain box scaled by the
	# fraction rather than a textured quad: this is the readout, and the art pass
	# can replace the body without touching it.
	_bar_max_width = size.x
	var bar := BoxMesh.new()
	bar.size = Vector3(_bar_max_width, 0.06, 0.06)
	_bar = MeshInstance3D.new()
	_bar.mesh = bar
	_bar.position = Vector3(0.0, height + 0.22, 0.0)
	_bar.material_override = CozyPixelArt.make_flat_material(
		Color(0.78, 0.26, 0.24))
	add_child(_bar)


# ---------------------------------------------------------------- being hit

func is_dead() -> bool:
	return hp <= 0.0


func health_fraction() -> float:
	return 0.0 if hp_max <= 0.0 else clampf(hp / hp_max, 0.0, 1.0)


## Take `amount` damage. Returns whether this killed it.
##
## `from` is recorded rather than assumed. It is the reason a drop can be paid to
## the killer instead of to whoever is closest when the health runs out, and it
## is one reference rather than a threat table — with one player those are the
## same answer, and the cheaper one is right until they are not.
func take_damage(amount: float, from: Node = null) -> bool:
	if is_dead():
		return false
	if from != null:
		_last_attacker = from
	hp = maxf(0.0, hp - maxf(0.0, amount))
	_update_bar()
	return is_dead()


func last_attacker() -> Node:
	return _last_attacker


func _update_bar() -> void:
	if _bar == null:
		return
	var frac := health_fraction()
	# Scale rather than rebuild: a bar is asked for its length every frame it is
	# visible, and a new BoxMesh per frame is a new resource per frame.
	_bar.scale = Vector3(maxf(frac, 0.001), 1.0, 1.0)
	# Anchored at the LEFT end, so it empties toward the left the way a bar does
	# rather than shrinking toward its own middle.
	_bar.position.x = -_bar_max_width * 0.5 * (1.0 - frac)
	_bar.visible = frac > 0.0 and frac < 1.0


func describe() -> String:
	return "%s %d/%d" % [CozyMonsterDefs.display_name(def_id), int(hp), int(hp_max)]
