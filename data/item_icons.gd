class_name CozyItemIcons
extends RefCounted
## Which picture stands for which id, and — just as importantly — WHICH IDS HAVE
## NO PICTURE YET.
##
## ---------------------------------------------------------------------------
## ONE TABLE FOR ITEMS AND MATERIALS, because the game does not have two kinds of
## thing to draw: a cell in the bag holds an equipment instance and a row in the
## pack holds a material, and both are "an id from the game's vocabulary" with a
## sprite beside it. Splitting the table would mean two places to look and two
## chances to miss one.
##
## ---------------------------------------------------------------------------
## THE ART IS KENNEY'S, CC0 (`docs/CREDITS.md`), 16x16, cut from one sheet that is
## COMMITTED WHOLE so a tile can be traced back to the sheet it came from.
##
## ## WHAT IS MAPPED AND WHAT IS NOT
##
## EVERY entry below was checked by LOOKING at the tile, and an id is mapped only
## when the reading is honest. That is the whole discipline of this file: a
## plausible-looking wrong icon is worse than no icon, because a bag that shows a
## hammer over an axe is a bug report about a lie — the same argument
## `CozyItemInstance.appearance_name` makes about names.
##
## So `wood` maps to a wooden branch and `copper` to a pile of coins. `berry_pie`
## does NOT map to the pie on the sheet, because "that brown round thing is
## probably bread" is a guess — see `missing()`, which lists what has no picture
## rather than letting the gap be silence.

## The directory the cut tiles live in.
const ICON_DIR := "res://assets/art/pixel/kenney"

## id -> file name (without the extension) in `ICON_DIR`.
##
## The ids are `CozyItemDefs.ids()` and `CozyMaterials.MATERIALS` keys, and
## `test_item_icons` asserts every file named here exists — a path is a promise
## that can be broken by deleting a file, and a broken one is a cell that draws
## nothing with no error to say why.
const ICONS := {
	# Materials -------------------------------------------------------------
	"wood": "icon_branch",        # a branch, because wood is what a tree gave you
	"stick": "icon_branch",       # ...and a stick is the same branch, seen again
	"copper": "icon_coin",
	"tent": "icon_tent",
	# Equipment -------------------------------------------------------------
	"wooden_shield": "icon_shield",
	"cloth_armor": "icon_tunic",  # a garment — the tile IS clothing, not cloth
}


## The picture for an id, or null when there is none.
##
## NULL IS AN ANSWER, and the callers are written for it: the bag draws the name it
## already drew, so an unmapped id looks exactly like the game did before there
## were icons at all.
static func icon_for(id: String) -> Texture2D:
	var file := String(ICONS.get(id, ""))
	if file == "":
		return null
	var path := "%s/%s.png" % [ICON_DIR, file]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func has_icon(id: String) -> bool:
	return ICONS.has(id)


## Every id the game can draw that has NO picture yet, sorted.
##
## THE WORK LIST, measured rather than remembered: "we still need icons" is a
## sentence nobody can act on, and "eleven of nineteen" is one somebody can.
static func missing() -> Array[String]:
	var out: Array[String] = []
	for id in CozyItemDefs.ids():
		if not ICONS.has(id):
			out.append(id)
	for id in CozyMaterials.MATERIALS:
		if not ICONS.has(String(id)):
			out.append(String(id))
	out.sort()
	return out


## Every id the game can draw, mapped or not. The denominator of the work list,
## so a table that quietly lost a row cannot look like progress.
static func drawable_ids() -> Array[String]:
	var out: Array[String] = []
	for id in CozyItemDefs.ids():
		out.append(id)
	for id in CozyMaterials.MATERIALS:
		out.append(String(id))
	out.sort()
	return out
