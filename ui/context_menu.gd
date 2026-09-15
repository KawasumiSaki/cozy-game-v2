class_name CozyContextMenu
extends PopupPanel
## Right-click context menu.
##
## Willow's design, and it solves a problem the interface had without one:
## before this there was no way to SELECT anything. Left-click is taken by
## placing, so the only things the player could reach were the ones on the tool
## palette — the whole world was unclickable.
##
## It is also what finally makes terrain editing reachable. CozyTerrainIntent
## has existed since V2-11 with no way to invoke it from the game; it is now one
## item away from a right-click on the ground.
##
## The menu is built from what is actually under the cursor rather than from a
## fixed list, so it never offers an action that would do nothing.

signal action_chosen(id: String, target: Variant)

const WIDTH := 150

var _box: VBoxContainer = null
var _target: Variant = null


func _ready() -> void:
	# A pixel panel, not a themed OS popup: the default PopupPanel brings
	# rounded corners and a drop shadow, both of which read as a different game.
	var panel := CozyUiTheme.panel_style(CozyUiTheme.PANEL_BG_SOLID)
	panel.set_content_margin_all(4)
	add_theme_stylebox_override("panel", panel)
	transparent_bg = false

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)

	popup_hide.connect(_on_closed)


## `entries` is an Array of {id, label, hint} — hint is optional and drawn dim,
## for the thing the action applies to.
func open_for(entries: Array, at: Vector2, target: Variant = null) -> void:
	_target = target
	for c in _box.get_children():
		c.queue_free()

	var title := Label.new()
	title.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
	title.add_theme_color_override("font_color", CozyUiTheme.TEXT_DIM)
	title.text = String(target["title"]) if target is Dictionary and target.has("title") else "Actions"
	title.custom_minimum_size = Vector2(WIDTH, 0)
	_box.add_child(title)

	var rule := ColorRect.new()
	rule.color = CozyUiTheme.PANEL_BORDER_DIM
	rule.custom_minimum_size = Vector2(WIDTH, 1)
	_box.add_child(rule)

	for e in entries:
		var b := Button.new()
		b.text = String(e["label"])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(WIDTH, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE)
		b.add_theme_stylebox_override("normal", CozyUiTheme.button_style(false))
		b.add_theme_stylebox_override("hover", CozyUiTheme.button_style_hover())
		b.add_theme_stylebox_override("pressed", CozyUiTheme.button_style(true))
		b.add_theme_stylebox_override("focus", CozyUiTheme.button_style(false))
		b.add_theme_color_override("font_color", CozyUiTheme.TEXT)
		if e.has("hint") and String(e["hint"]) != "":
			b.tooltip_text = String(e["hint"])
		# AN ENTRY CAN BE SHOWN AND NOT AVAILABLE, which is the point of it. A verb
		# that vanishes when it cannot be used leaves the player guessing whether
		# the game forgot it, whether they are standing in the wrong place, or
		# whether the tree is simply spent — and `hint` already says which of the
		# three. Deleting the button answers none of them.
		b.disabled = bool(e.get("disabled", false))
		b.pressed.connect(_on_entry.bind(String(e["id"])))
		_box.add_child(b)

	# Shown at the cursor, then nudged back inside the window so a right-click
	# near the edge does not put the menu off screen.
	#
	# Note: a PopupPanel is a Window, not a Control, so there is no
	# get_viewport_rect() here — the root Window's size is what we want, and its
	# content scale is already folded in.
	popup(Rect2i(Vector2i(at), Vector2i(WIDTH, 0)))
	var vp := Vector2(get_tree().root.size)
	var sz := size
	var pos := position
	pos.x = mini(pos.x, int(vp.x - sz.x - CozyUiTheme.GAP))
	pos.y = mini(pos.y, int(vp.y - sz.y - CozyUiTheme.GAP))
	position = Vector2i(maxi(pos.x, 0), maxi(pos.y, 0))


func _on_entry(id: String) -> void:
	hide()
	action_chosen.emit(id, _target)


func _on_closed() -> void:
	_target = null


func entry_count() -> int:
	# Minus the title and the rule, which are not actions.
	return maxi(0, _box.get_child_count() - 2)


func entry_labels() -> Array[String]:
	var out: Array[String] = []
	for c in _box.get_children():
		if c is Button:
			out.append(c.text)
	return out


## Invoke an entry by its label, taking the same path a click does.
func press(label: String) -> bool:
	for c in _box.get_children():
		if c is Button and c.text == label:
			c.emit_signal("pressed")
			return true
	return false
