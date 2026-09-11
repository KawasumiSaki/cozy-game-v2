class_name CozyAssetDefinition
extends RefCounted
## Asset Definition metadata (V2.1 doc E.4).
##
## Every production asset carries one of these. Doc E.4.2 gives the reason: with
## 100 grasses, 50 flowers, 30 rocks and 40 VFX in the library, filenames alone
## cannot tell a runtime generator whether something may sit by water, appear
## beside a road, belong in a forest, or needs a shadow.
##
## E.3.1 also fixes a three-state lifecycle and forbids shipping raw generator
## output:
##
##     RAW -> CLEANED -> APPROVED
##
##     "禁止直接把 AI 原图放进正式运行目录。"
##
## That rule is enforced by the library, not merely documented: only APPROVED
## definitions are ever handed to runtime systems.

enum State { RAW, CLEANED, APPROVED }

const STATE_NAMES := {
	State.RAW: "raw",
	State.CLEANED: "cleaned",
	State.APPROVED: "approved",
}

## Fields a definition cannot be useful without (doc E.4.1).
const REQUIRED: Array[String] = ["id", "category", "source", "state", "resolution", "pivot"]

var id := ""
var category := ""
var subcategory := ""
var style_set := ""
var source := ""
var license := ""
var resolution := Vector2i.ZERO
var pixel_scale := 1
var pivot := Vector2(0.5, 1.0)
var anchor := "bottom_center"
var billboard := true
var casts_shadow := false
var biomes: Array[String] = []
var tags: Array[String] = []
var variants := 1
var state: State = State.RAW

## Where this definition was read from — diagnostics only, never gameplay.
var source_path := ""


static func from_dict(d: Dictionary, from_path := "") -> CozyAssetDefinition:
	var a := CozyAssetDefinition.new()
	a.source_path = from_path
	a.id = String(d.get("id", ""))
	a.category = String(d.get("category", ""))
	a.subcategory = String(d.get("subcategory", ""))
	a.style_set = String(d.get("style_set", ""))
	a.source = String(d.get("source", ""))
	a.license = String(d.get("license", ""))
	a.pixel_scale = int(d.get("pixel_scale", 1))
	a.anchor = String(d.get("anchor", "bottom_center"))
	a.billboard = bool(d.get("billboard", true))
	a.casts_shadow = bool(d.get("casts_shadow", false))
	a.variants = maxi(1, int(d.get("variants", 1)))
	a.state = state_from_name(String(d.get("state", "raw")))

	var res = d.get("resolution", null)
	if res is Array and res.size() >= 2:
		a.resolution = Vector2i(int(res[0]), int(res[1]))

	var piv = d.get("pivot", null)
	if piv is Array and piv.size() >= 2:
		a.pivot = Vector2(float(piv[0]), float(piv[1]))

	for b in d.get("biomes", []):
		a.biomes.append(String(b))
	for t in d.get("tags", []):
		a.tags.append(String(t))

	return a


func to_dict() -> Dictionary:
	return {
		"id": id,
		"category": category,
		"subcategory": subcategory,
		"style_set": style_set,
		"source": source,
		"license": license,
		"resolution": [resolution.x, resolution.y],
		"pixel_scale": pixel_scale,
		"pivot": [pivot.x, pivot.y],
		"anchor": anchor,
		"billboard": billboard,
		"casts_shadow": casts_shadow,
		"biomes": biomes,
		"tags": tags,
		"variants": variants,
		"state": state_name(),
	}


# ---------------------------------------------------------------- states

static func state_from_name(n: String) -> State:
	match n.to_lower():
		"approved":
			return State.APPROVED
		"cleaned":
			return State.CLEANED
		_:
			return State.RAW


func state_name() -> String:
	return STATE_NAMES.get(state, "raw")


## Only APPROVED assets may reach runtime systems (doc E.3.1).
func is_runtime_ready() -> bool:
	return state == State.APPROVED


# ---------------------------------------------------------------- validation

## Returns a list of problems; empty means the definition is usable.
##
## Strict on purpose. Doc E.4.2's whole point is that a runtime generator must
## be able to TRUST what it queries, so a half-specified asset is a bug worth
## surfacing loudly rather than tolerating quietly.
func validate() -> Array[String]:
	var problems: Array[String] = []

	for field in REQUIRED:
		var missing := false
		match field:
			"id":
				missing = id.strip_edges() == ""
			"category":
				missing = category.strip_edges() == ""
			"source":
				missing = source.strip_edges() == ""
			"resolution":
				missing = resolution.x <= 0 or resolution.y <= 0
			"pivot":
				missing = pivot.x < 0.0 or pivot.x > 1.0 or pivot.y < 0.0 or pivot.y > 1.0
			"state":
				missing = false   # any state parses; unknown names fall back to RAW
		if missing:
			problems.append("missing or invalid '%s'" % field)

	if pixel_scale < 1:
		problems.append("pixel_scale must be >= 1")
	if variants < 1:
		problems.append("variants must be >= 1")

	return problems


func has_biome(b: String) -> bool:
	return biomes.has(b)


func has_tag(t: String) -> bool:
	return tags.has(t)


func describe() -> String:
	return "%s [%s/%s] %dx%d %s biomes=%s" % [
		id, category, subcategory, resolution.x, resolution.y,
		state_name(), str(biomes)]
