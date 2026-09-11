class_name CozyRoof
extends Node3D
## A deliberately SIMPLE flat roof.
##
## The doc's roof generator (#34–#37) derives gable / hip / flat roofs from the
## room polygon and adapts them as walls move. That is real work, and none of it
## is needed to prove the game loop — so this is a slab. Swap it out later.
##
## What it DOES have to do is occlude and fade (#12.2 Interior Fade). A roof
## that cannot fade hides the player the moment they walk inside, which makes
## the whole "walk into your house" acceptance test impossible.

var _mat: StandardMaterial3D = null
var _body: StaticBody3D = null
var _fade := 1.0


func setup(size: Vector3, mat_id := "brick") -> void:
	var bm := BoxMesh.new()
	bm.size = size

	var mi := MeshInstance3D.new()
	mi.mesh = bm
	_mat = CozyMaterials.get_material(mat_id,
		Vector3(maxf(size.x / 2.0, 1.0), maxf(size.z / 2.0, 1.0), 1.0))
	mi.material_override = _mat
	add_child(mi)

	# The collider exists so the occlusion ray has something to hit.
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)


## Same duck-typed interface as CozyWall, so the occlusion system can treat
## walls and roofs identically.
func bodies() -> Array:
	return [_body]


func set_fade(a: float) -> void:
	if is_equal_approx(a, _fade) or _mat == null:
		return
	_fade = a
	if a >= 0.999:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_mat.albedo_color = Color(1, 1, 1, 1)
	else:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1, 1, 1, a)
