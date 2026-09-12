class_name CozyCharacterVisuals
extends RefCounted
## How a character's DATA becomes the sprites on screen (ART-14).
##
## Two jobs, and they are separate on purpose:
##
##   1. WHICH animation should be playing — `select()`. Pure logic, no art.
##   2. WHERE those frames come from — `frames_for()`. A rendered sheet if the
##      factory has produced one, the procedural placeholder if it has not.
##
## Divider between them is the whole point of the Hybrid Pixel Diorama pipeline:
## Blender renders sheets offline, the game loads them, and NOTHING in the game
## knows or cares which of the two it got. Doc 58.1 requires exactly this —
## "美术资源可以为空，系统不能依赖资源本身才能运行".

## Every animation a character can be in. This is the contract with the factory:
## it must render one sheet per entry, with FRAMES[anim] frames in a row.
const ANIMATIONS: Array[String] = ["idle", "walk", "work", "sit", "sleep"]

## Frames per animation, and playback speed. The factory MUST match the counts —
## a sheet with the wrong number of columns plays as garbage, and it plays as
## garbage silently, which is why `_check_character_sheets` cross-checks them.
const FRAMES := {"idle": 2, "walk": 4, "work": 2, "sit": 1, "sleep": 2}
const FPS := {"idle": 3.0, "walk": 8.0, "work": 3.0, "sit": 2.0, "sleep": 1.5}

const SHEET_ROOT := "res://assets/art/pixel/characters"


## Which animation this character should be playing.
##
## MEASURED, not guessed (2026-09-12). The obvious implementation reads the FSM,
## and it is wrong: the FSM has three states (IDLE / GOING / WORKING) while the
## schedule has six activities, and SLEEPING AND EATING BOTH HAPPEN WHILE
## `fsm_state == WORKING`. Selecting on the FSM alone plays `work` through a
## resident's entire sleep, and nothing reports it — the character just looks
## busy while unconscious.
##
## So: locomotion first, then whether there is a task at all, and only then the
## activity. Each step is load-bearing.
static func select(activity: String, moving: bool, busy: bool) -> String:
	# A resident walking to bed is WALKING. Locomotion outranks intent.
	if moving:
		return "walk"
	# Standing around with nothing acquired yet.
	if not busy:
		return "idle"
	if activity == "sleep":
		return "sleep"
	# Eating, leisure and socialising all resolve to the SAME `sit` interaction
	# point (see `CozySchedule.ACTIVITY_POINTS`), so they are one pose. Read from
	# that table rather than retyped here — it is documented as the only place
	# the activity-to-point bridge exists, and a second copy is how the two drift.
	if sit_activities().has(activity):
		return "sit"
	return "work"


## Which activities put the resident on a seat. Derived, never retyped.
static func sit_activities() -> Array[String]:
	var out: Array[String] = []
	for a in CozySchedule.ACTIVITY_POINTS:
		if String(CozySchedule.ACTIVITY_POINTS[a]) == "sit":
			out.append(String(a))
	out.sort()
	return out


## Every animation `select()` can actually return, over the whole activity
## vocabulary. Used to prove nothing is rendered that can never play — the
## "declared capability with no consumer" trap this project has paid for five
## times. A `carry` sheet would show up here as unreachable.
static func reachable_animations() -> Array[String]:
	var seen := {}
	var vocabulary: Array = CozySchedule.ACTIVITY_POINTS.keys()
	# "" is the player and any character with no schedule at all.
	vocabulary.append("")
	for moving in [true, false]:
		for busy in [true, false]:
			for a in vocabulary:
				seen[select(String(a), moving, busy)] = true
	var out: Array[String] = []
	for k in seen:
		out.append(String(k))
	out.sort()
	return out


## Where the factory's sheets for one appearance live.
##
## One directory per appearance, one PNG per animation. The appearance IS the
## path: there is no lookup table to keep in sync, and a missing render is a
## missing file rather than a missing entry.
static func sheet_dir(appearance: Dictionary) -> String:
	var a := CozyAppearanceDefs.normalise(appearance)
	return "%s/%s/%s__%s__%s__%s" % [
		SHEET_ROOT, a["body"], a["hair"], a["face"], a["clothes"], a["color"]]


static func sheet_path(appearance: Dictionary, anim: String) -> String:
	return "%s/%s.png" % [sheet_dir(appearance), anim]


## All-or-nothing on purpose. A half-rendered character would play real art for
## some states and placeholders for others, which reads as a broken game rather
## than as missing art. Either the factory has produced the whole set or none of
## it is used.
static func is_rendered(appearance: Dictionary) -> bool:
	for anim in ANIMATIONS:
		if not ResourceLoader.exists(sheet_path(appearance, anim)):
			return false
	return true


## The frames this appearance should use. Rendered if it exists, placeholder if
## not — and the caller cannot tell the difference, which is the point.
static func frames_for(appearance: Dictionary) -> SpriteFrames:
	if is_rendered(appearance):
		var real := _load_rendered(appearance)
		if real != null:
			return real
	return build_placeholder(appearance)


static func _load_rendered(appearance: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIMATIONS:
		var tex := load(sheet_path(appearance, anim)) as Texture2D
		if tex == null:
			return null
		# The sheet is one row of frames, so the column count IS the frame count.
		var columns := int(FRAMES[anim])
		sf.add_animation(anim)
		sf.set_animation_speed(anim, float(FPS[anim]))
		for i in columns:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(
				float(i) * float(tex.get_width()) / float(columns), 0.0,
				float(tex.get_width()) / float(columns), float(tex.get_height()))
			sf.add_frame(anim, at)
	return sf


## The Phase 0 stand-in: the same blocky 16x24 figure, posed per animation.
##
## It exists so the pipeline can be built, asserted and seen BEFORE any art
## exists — not as a fallback anyone should ship. Every appearance renders a
## visibly different figure (skin, hair and cloth all come from the data), so a
## wrong id is caught by looking rather than by reading.
static func build_placeholder(appearance: Dictionary) -> SpriteFrames:
	var a := CozyAppearanceDefs.normalise(appearance)
	var skin := CozyAppearanceDefs.skin_of(a)
	var hair := CozyAppearanceDefs.hair_tint_of(a)
	var cloth := CozyAppearanceDefs.cloth_tint_of(a)

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIMATIONS:
		sf.add_animation(anim)
		sf.set_animation_speed(anim, float(FPS[anim]))
		sf.set_animation_loop(anim, true)
		for i in int(FRAMES[anim]):
			sf.add_frame(anim, CozyPixelArt.make_character_texture(skin, cloth, hair, anim, i))
	return sf
