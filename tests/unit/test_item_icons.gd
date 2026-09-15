extends "res://tests/unit/unit_test.gd"
## Which id wears which picture (Kenney, CC0 — `docs/CREDITS.md`).
##
## The table is small and the interesting half is what is NOT in it. Two failures
## are available and only one of them is loud:
##
##   1. A MAPPED ID WHOSE FILE IS GONE. A path is a promise that can be broken by
##      deleting a file, and a broken one draws NOTHING with no error — the cell
##      simply comes up blank, which reads as a bug in the panel.
##   2. AN UNMAPPED ID. Nothing is wrong and nothing is drawn; the game looks
##      exactly as it did before there were icons at all. So it is not a failure —
##      it is a WORK LIST, and this suite measures it so it cannot be mistaken for
##      "the icons are done".
##
## No world, no frames. The table and the files.

const ICON_DIR := "res://assets/art/pixel/kenney"


func _init() -> void:
	suite("item icons")
	case("every mapped id has a file, and it loads", _files_resolve)
	case("an id with no picture answers null rather than failing", _unmapped_is_null)
	case("the two that reach a cell really do", _the_visible_ones)
	case("the work list is measured, not remembered", _work_list)


## The loud one. `ResourceLoader.exists` before `load`, because `load` on a missing
## path pushes an ERROR — and a check that proves a refusal must not make `0 ERROR`
## a lie (INVARIANTS: "a line that means the probe worked must not look like the
## line that means the build is broken").
func _files_resolve() -> void:
	is_true("there is something in the table", CozyItemIcons.ICONS.size() > 0)
	for id in CozyItemIcons.ICONS:
		var file := String(CozyItemIcons.ICONS[id])
		var path := "%s/%s.png" % [ICON_DIR, file]
		is_true("'%s' names a file that exists (%s)" % [id, file],
			ResourceLoader.exists(path))
		var tex := CozyItemIcons.icon_for(String(id))
		is_true("and it loads as a texture" if tex != null else
			"and it loads as a texture ('%s')" % id, tex != null)
		if tex != null:
			# 16x16, because `ART_PROFILE` §4 says a pixel sprite is shown at the
			# size it was drawn: anything else is a resample and a soft edge.
			is_true("'%s' is a 16 px tile (%d x %d)" % [id, tex.get_width(), tex.get_height()],
				tex.get_width() == 16 and tex.get_height() == 16)


func _unmapped_is_null() -> void:
	eq("an id nobody drew answers null", CozyItemIcons.icon_for("nothing_like_this"), null)
	is_false("and says so", CozyItemIcons.has_icon("nothing_like_this"))
	# The control: a mapped one answers with something, or the case above would pass
	# against a table that returned null for everything.
	is_true("while a mapped one does not", CozyItemIcons.icon_for("copper") != null)


## The two entries that actually reach a screen, checked by name: a shield sits in
## a bag cell and a garment sits in a gear cell, and both are equipment INSTANCES.
## An `icon_for` that took a definition id and was handed an instance id instead
## would be blank on exactly these two and correct everywhere the tests look.
func _the_visible_ones() -> void:
	for id in ["wooden_shield", "cloth_armor"]:
		is_true("'%s' is a real item definition" % id, CozyItemDefs.exists(id))
		is_true("and it has a picture" if CozyItemIcons.has_icon(id) else
			"and it has a picture ('%s')" % id, CozyItemIcons.has_icon(id))


## THE NUMBER, rather than the sentence. "We still need icons" is not actionable;
## "11 of 19" is — and a table that quietly lost a row cannot look like progress,
## because the denominator comes from the vocabularies rather than from the table.
func _work_list() -> void:
	var missing := CozyItemIcons.missing()
	var all := CozyItemIcons.drawable_ids()
	is_true("the vocabulary is bigger than the table", all.size() > CozyItemIcons.ICONS.size())
	is_true("the work list names what is left (%d of %d)" % [missing.size(), all.size()],
		missing.size() == all.size() - CozyItemIcons.ICONS.size())
	# Nothing is both mapped and missing, which is what a typo in either direction
	# looks like: `materials` mapped as `material` is an entry for a thing that does
	# not exist, and it would never be noticed.
	for id in CozyItemIcons.ICONS:
		is_true("'%s' is something the game can actually draw" % id, all.has(String(id)))
