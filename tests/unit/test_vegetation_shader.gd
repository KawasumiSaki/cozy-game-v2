extends "res://tests/unit/unit_test.gd"
## The moving-billboard vegetation shader, and the two ways it fails QUIETLY.
##
## 1. `set_shader_parameter` accepts a name the shader does not have and drops it
##    on the floor — no error, no warning, and the plant keeps the default from
##    the shader file. So a rename on either side of the GDScript/shader boundary
##    is invisible: the grass still renders, it just stops moving, or starts
##    moving like whatever the old default was. The names are checked against the
##    shader's own uniform list below.
## 2. The shader rotates each quad about `quad_half_height`, and the scatter
##    lifts each quad by the same number. If they disagree, the plant pivots
##    about a point that is not where it meets the ground and swings through it.
##    Neither file can see the other's number, so the table is checked here.
##
## The sprite itself is a placeholder and this suite does not care what it looks
## like — a shader that draws nothing passes every check in this file.

const VEGETATION_SHADER := "res://shaders/vegetation.gdshader"


func _init() -> void:
	suite("vegetation shader")
	case("the shader loads", _loads)
	case("every parameter we set is one it has", _names_match)
	case("every drawn asset has a wind strength", _wind_table_covers)
	case("a rock does not move", _rock_is_still)
	case("the half-height reaches the shader", _half_height)
	case("the wind field is generated, not shipped", _wind_is_procedural)
	case("every uniform is either per-asset or named as tuning", _no_orphan_uniforms)


func _loads() -> void:
	var s: Shader = load(VEGETATION_SHADER)
	is_true("the shader is there", s != null)


## THE CHECK THIS SUITE EXISTS FOR. See the header.
func _names_match() -> void:
	var shader: Shader = load(VEGETATION_SHADER)
	var have := {}
	for u in shader.get_shader_uniform_list():
		have[String(u["name"])] = true
	var want := CozyPixelArt.vegetation_parameters(0.5, 1.0, null, null)
	is_true("the parameter list is not empty", want.size() > 0)
	for name in want:
		is_true("the shader has a uniform named '%s'" % name, have.has(name))


## A plant drawn without an entry in `WIND_STRENGTH` still renders — it just gets
## the `.get(asset_id, 1.0)` fallback, which is grass-like motion on whatever it
## is. A rock tree that sways is the failure, and it has no symptom until someone
## looks at it.
func _wind_table_covers() -> void:
	for asset_id in CozyVegetationScatter.PLACEHOLDER_SIZE:
		is_true("'%s' has a wind strength" % asset_id,
			CozyVegetationScatter.WIND_STRENGTH.has(asset_id))


func _rock_is_still() -> void:
	eq("the rock's wind strength is zero",
		CozyVegetationScatter.WIND_STRENGTH["rock_small_01"], 0.0)
	is_true("and the grass's is not",
		float(CozyVegetationScatter.WIND_STRENGTH["grass_tuft_01"]) > 0.0)


func _half_height() -> void:
	var mat := CozyPixelArt.make_vegetation_material(null, 0.275, 0.0)
	eq("the half-height reaches the shader",
		mat.get_shader_parameter("quad_half_height"), 0.275)
	eq("and so does the strength",
		mat.get_shader_parameter("wind_strength"), 0.0)
	eq("and the texture it was given",
		mat.get_shader_parameter("albedo_texture"), null)


## PROCEDURAL, and this is the assertion that keeps it that way: a noise field
## committed as a PNG would be an art asset nobody drew, and it would then owe a
## line in `docs/CREDITS.md` saying where it came from.
## What `CozyPixelArt` drives, per asset, from GDScript.
const PER_ASSET := ["albedo_texture", "wind_noise", "quad_half_height", "wind_strength"]

## World-level tuning that currently lives in the shader file with a default:
## the strength of the wind, how fast it travels, how far a plant bends, how
## often the animation steps, and how much the plants vary. Listed rather than
## left implicit so that a knob added to make ONE asset look right shows up as a
## decision instead of as a default nobody chose.
##
## These are what the wind system (ENV V0.3) will eventually own, the same way
## `CozyTimeSystem` owns the clock the day/night code reads — at which point they
## move into `PER_ASSET`'s side of this list.
const WORLD_TUNING := ["tint", "alpha_scissor", "wind_direction", "wind_scale",
	"wind_speed", "wind_threshold", "wind_angle", "noise_diverge_angle",
	"framerate", "quantised", "height_variety", "lean_variety"]


## A uniform nothing writes is a knob that does nothing — this project's
## recurring "declared with no consumer" shape, and in a shader it is worse than
## usual because the default in the .gdshader makes it LOOK like it works.
func _no_orphan_uniforms() -> void:
	var shader: Shader = load(VEGETATION_SHADER)
	for u in shader.get_shader_uniform_list():
		var name := String(u["name"])
		is_true("'%s' is per-asset or named as world tuning" % name,
			PER_ASSET.has(name) or WORLD_TUNING.has(name))


func _wind_is_procedural() -> void:
	var tex := CozyPixelArt.make_wind_noise()
	is_true("the wind field is a NoiseTexture2D", tex is NoiseTexture2D)
	is_true("and it is seamless", (tex as NoiseTexture2D).seamless)
	var twice := CozyPixelArt.wind_noise()
	is_true("and every plant shares the one field", twice == CozyPixelArt.wind_noise())
