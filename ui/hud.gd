class_name CozyHud
extends CanvasLayer
## The interface. PC-first; touch comes later.
##
## What it replaced: a single Label with six lines of text. Everything was
## there and nothing was findable — the tool list, the resources and the camera
## state all shared one block of monospaced prose.
##
## LAYOUT, and why:
##
##   top strip    mode + camera on the left, feedback on the right
##   bottom bar   resources on the left, tools in the centre, context right
##
## Mode and camera sit together because both answer "what will my input do?".
## Feedback sits far from the tools so a refusal never covers the button you
## just pressed. Resources are bottom-left and context bottom-right because both
## are read, not acted on, and the tools — the only clickable things — take the
## centre where the eye already is.
##
## The tool buttons are CLICKABLE, which is new. Cycling with TAB was a
## keyboard-only affordance that also required remembering the order.

signal tool_selected(index: int)
signal build_mode_toggled(on: bool)
## A category was opened. `main.gd` listens because opening one is not always a
## HUD matter — the resident panel belongs to the game, not to the bar.
signal category_selected(id: String)

## The seven categories, in Willow's order (2026-09-14).
##
## ASCII NAMES, because game text has to be ASCII: a font that cannot draw a
## character draws a box, and the rule exists because this project has paid for
## it once already.
##
## `built` IS NOT DECORATION. A category with nothing behind it opens onto a line
## saying what it is WAITING FOR rather than a button that does nothing when
## pressed. A dead button is a claim that something is there — the same
## "declared capability with no consumer" this project has seven entries about.
##
## The names are the document's, translated: Plan / Tools / Inventory / Craft /
## Build / Trade / People. Building is parked (`BUILDING_ENABLED`), and the note
## says so rather than leaving the category empty for no stated reason.
const CATEGORIES := [
	{"id": "plan", "name": "Plan", "built": false,
		"note": "work priorities, and who does what when"},
	{"id": "tools", "name": "Tools", "built": true, "note": ""},
	{"id": "inventory", "name": "Inventory", "built": true, "note": ""},
	{"id": "craft", "name": "Craft", "built": false, "note": "recipes"},
	{"id": "build", "name": "Build", "built": false,
		"note": "parked with the building system"},
	{"id": "trade", "name": "Trade", "built": false, "note": "buying and selling"},
	{"id": "people", "name": "People", "built": true, "note": ""},
]

const TOP_H := CozyUiTheme.STRIP_H
const BOTTOM_H := CozyUiTheme.BAR_H

## Which category is open. Tools by default, because it is the one with content
## — an app that opens on an empty page teaches the player it is empty.
var _active_category := 1
var _category_box: HBoxContainer = null
var _category_buttons: Array[Button] = []
var _category_panel: PanelContainer = null
var _category_note: Label = null
var _category_open := true

var _tools: Array[String] = []
var _tool_buttons: Array[Button] = []
var _tool_hotkey_labels: Array[Label] = []
var _selected := 0

var _resources_box: HBoxContainer = null
var _resource_labels: Dictionary = {}
var _resource_icons: Dictionary = {}

var _mode_label: Label = null
var _camera_label: Label = null
var _clock_label: Label = null
var _message_label: Label = null
var _context_label: Label = null

var _panel_count := 0

## What the last right-click selected. Right-aligned above the bar, out of the
## way until there is something to say.
var _info_panel: PanelContainer = null
var _info_title: Label = null
var _info_body: Label = null


func _ready() -> void:
	_build_top()
	_build_bottom()
	_build_category_panel()
	_build_info()
	_apply_category()


func _build_info() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	_info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_info_panel.offset_left = -230
	_info_panel.offset_top = -(BOTTOM_H + 96)
	_info_panel.offset_bottom = -(BOTTOM_H + CozyUiTheme.GAP)
	_info_panel.visible = false
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_info_title = _mk_label(CozyUiTheme.ACCENT)
	_info_body = _mk_label(CozyUiTheme.TEXT)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_title)
	col.add_child(_info_body)
	_info_panel.add_child(col)
	add_child(_info_panel)
	_panel_count += 1


## Selecting something finally has somewhere to land. Before this the world was
## unclickable and there was no way to ask what a thing was.
func show_info(title: String, lines: Array) -> void:
	if _info_panel == null:
		return
	_info_title.text = title
	_info_body.text = "\n".join(lines)
	_info_panel.visible = true


func clear_info() -> void:
	if _info_panel:
		_info_panel.visible = false


func info_visible() -> bool:
	return _info_panel != null and _info_panel.visible


func info_title_text() -> String:
	return _info_title.text if _info_title else ""


func info_body_text() -> String:
	return _info_body.text if _info_body else ""


# ---------------------------------------------------------------- top strip

func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", CozyUiTheme.panel_style(
		CozyUiTheme.PANEL_BG, CozyUiTheme.PANEL_BORDER_DIM))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_H
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CozyUiTheme.GAP * 3)
	bar.add_child(row)

	_mode_label = _mk_label(CozyUiTheme.TEXT_STRONG)
	_camera_label = _mk_label(CozyUiTheme.TEXT_DIM)
	# The clock has existed since Phase 0 (`CozyTimeSystem.hh_mm()` / `season()`)
	# and was never shown anywhere — the resident's whole day turns on it, and the
	# player could not see what time it was.
	_clock_label = _mk_label(CozyUiTheme.TEXT)

	# Feedback right-aligned: it must never sit under the button just pressed.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_message_label = _mk_label(CozyUiTheme.OK)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	row.add_child(_mode_label)
	row.add_child(_camera_label)
	row.add_child(_clock_label)
	row.add_child(spacer)
	row.add_child(_message_label)
	add_child(bar)
	_panel_count += 1


# ---------------------------------------------------------------- bottom bar

func _build_bottom() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BOTTOM_H
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CozyUiTheme.GAP * 4)
	bar.add_child(row)

	_resources_box = HBoxContainer.new()
	_resources_box.add_theme_constant_override("separation", CozyUiTheme.GAP * 2)
	row.add_child(_resources_box)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	_category_box = HBoxContainer.new()
	_category_box.add_theme_constant_override("separation", CozyUiTheme.GAP)
	row.add_child(_category_box)
	for i in CATEGORIES.size():
		var c: Dictionary = CATEGORIES[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 22)
		b.text = String(c["name"])
		b.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
		b.add_theme_stylebox_override("normal", CozyUiTheme.button_style(false))
		b.add_theme_stylebox_override("hover", CozyUiTheme.button_style_hover())
		b.add_theme_stylebox_override("pressed", CozyUiTheme.button_style(true))
		b.add_theme_stylebox_override("focus", CozyUiTheme.button_style(false))
		b.add_theme_color_override("font_color",
			CozyUiTheme.TEXT if bool(c["built"]) else CozyUiTheme.TEXT_DIM)
		b.pressed.connect(_on_category_pressed.bind(i))
		_category_box.add_child(b)
		_category_buttons.append(b)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_r)

	_context_label = _mk_label(CozyUiTheme.TEXT_DIM)
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_context_label)

	add_child(bar)
	_panel_count += 1


var _tools_box: HBoxContainer = null


## The strip above the bar that the open category fills.
##
## A second row rather than a wider first one: seven category buttons AND nine
## tools AND the resource list AND the context line did not fit on one line, and
## the result read as clutter — which is what Willow reported seeing. Splitting
## them means the bar answers "which part of the game am I in" and the strip
## answers "what can I do here".
func _build_category_panel() -> void:
	_category_panel = PanelContainer.new()
	_category_panel.add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	_category_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_category_panel.offset_top = -(BOTTOM_H + CozyUiTheme.BAR_H)
	_category_panel.offset_bottom = -BOTTOM_H
	add_child(_category_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CozyUiTheme.GAP * 2)
	_category_panel.add_child(row)

	_tools_box = HBoxContainer.new()
	_tools_box.add_theme_constant_override("separation", CozyUiTheme.GAP)
	row.add_child(_tools_box)

	_category_note = _mk_label(CozyUiTheme.TEXT_DIM)
	row.add_child(_category_note)

	_panel_count += 1


func _on_category_pressed(i: int) -> void:
	# Pressing the open one closes it, so the strip can be put away.
	if i == _active_category and _category_open:
		_category_open = false
		_apply_category()
		return
	_active_category = i
	_category_open = true
	_apply_category()


func select_category(i: int) -> void:
	if i < 0 or i >= CATEGORIES.size():
		return
	_active_category = i
	_category_open = true
	_apply_category()


func _apply_category() -> void:
	for i in _category_buttons.size():
		var colour := CozyUiTheme.TEXT_DIM
		if i == _active_category and _category_open:
			colour = CozyUiTheme.TEXT_STRONG
		elif bool(CATEGORIES[i]["built"]):
			colour = CozyUiTheme.TEXT
		_category_buttons[i].add_theme_color_override("font_color", colour)

	var c: Dictionary = CATEGORIES[_active_category]
	var is_tools := String(c["id"]) == "tools"
	_tools_box.visible = is_tools
	_category_note.visible = not is_tools
	_category_note.text = "" if is_tools else "%s - not built yet: %s" % [c["name"], c["note"]]
	_category_panel.visible = _category_open
	category_selected.emit(String(c["id"]))


func active_category() -> String:
	return String(CATEGORIES[_active_category]["id"])


func category_open() -> bool:
	return _category_open


func category_count() -> int:
	return CATEGORIES.size()


func category_name(i: int) -> String:
	return String(CATEGORIES[i]["name"])


func category_is_built(i: int) -> bool:
	return bool(CATEGORIES[i]["built"])


func _mk_label(colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE)
	l.add_theme_color_override("font_color", colour)
	return l


# ---------------------------------------------------------------- tools

## Groups are separated by a rule. Doc #24 forbids listing Door beside Wall,
## but grouping also earns its keep on its own: build / terrain / place are
## three different kinds of action and reading them as one undifferentiated row
## makes the palette slower to scan than it needs to be.
func set_tool_groups(groups: Array) -> void:
	_tools.clear()
	for g in groups:
		for t in g:
			_tools.append(t)
	set_tools(_tools, groups)


func set_tools(tools: Array[String], groups: Array = []) -> void:
	_tools = tools
	for b in _tool_buttons:
		b.queue_free()
	_tool_buttons.clear()
	var group_starts := {}
	var n := 0
	for g in groups:
		if n > 0:
			group_starts[n] = true
		n += g.size()

	for i in tools.size():
		if group_starts.has(i):
			var rule := ColorRect.new()
			rule.color = CozyUiTheme.PANEL_BORDER_DIM
			rule.custom_minimum_size = Vector2(1, 20)
			_tools_box.add_child(rule)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE      # keyboard focus ring is noise here
		b.custom_minimum_size = Vector2(0, 22)
		b.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
		b.add_theme_stylebox_override("normal", CozyUiTheme.button_style(false))
		b.add_theme_stylebox_override("hover", CozyUiTheme.button_style_hover())
		b.add_theme_stylebox_override("pressed", CozyUiTheme.button_style(true))
		b.add_theme_stylebox_override("focus", CozyUiTheme.button_style(false))
		b.add_theme_color_override("font_color", CozyUiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", CozyUiTheme.TEXT_STRONG)

		# Icon + label + hotkey. A palette that hides its shortcuts teaches nobody
		# the shortcuts — and this comment claimed the hotkey was shown for as long
		# as the palette existed, while nothing printed it (debt 14).
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = CozyPixelArt.make_tool_icon(tools[i])
		icon.custom_minimum_size = Vector2(CozyUiTheme.ICON, CozyUiTheme.ICON)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)
		var name_label := Label.new()
		name_label.text = _tool_name(tools[i])
		name_label.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(name_label)
		var key_label := Label.new()
		key_label.text = hotkey_name(i)
		key_label.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
		key_label.add_theme_color_override("font_color", CozyUiTheme.TEXT_DIM)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(key_label)
		_tool_hotkey_labels.append(key_label)
		b.add_child(inner)

		b.pressed.connect(_on_tool_pressed.bind(i))
		_tools_box.add_child(b)
		_tool_buttons.append(b)

	_apply_selection()


## Tools are numbered 1..9 then 0, so ten of them fit a row without a modifier.
##
## The palette has since outgrown that: an eleventh tool would repeat "1" on the
## same row. Shift extends the SAME scheme rather than inventing a second one, so
## the eleventh tool reads "S1" and the row still teaches its own shortcuts —
## which is the whole point of printing them (debt 14).
static func hotkey_name(index: int) -> String:
	if index < 0:
		return ""
	if index < 10:
		return str((index + 1) % 10)
	if index < 20:
		return "S" + str((index - 9) % 10)
	return ""


## Which tool index a digit key selects. 0 means the tenth tool, not the first.
## `shifted` selects the second ten.
static func index_for_hotkey(digit: int, shifted := false) -> int:
	if shifted:
		return 19 if digit == 0 else 9 + digit
	return 9 if digit == 0 else digit - 1


## Inverse of `hotkey_name`, for checks that read the printed LABEL rather than a
## keycode. Kept next to its pair so the two cannot drift.
static func index_for_hotkey_text(text: String) -> int:
	var t := text.strip_edges()
	var shifted := t.begins_with("S")
	if shifted:
		t = t.substr(1)
	if not t.is_valid_int():
		return -1
	return index_for_hotkey(int(t) % 10, shifted)


func set_clock(text: String) -> void:
	if _clock_label != null:
		_clock_label.text = text


func clock_text() -> String:
	return _clock_label.text if _clock_label != null else ""


func tool_hotkey_text(i: int) -> String:
	if i < 0 or i >= _tool_hotkey_labels.size():
		return ""
	return _tool_hotkey_labels[i].text


func _tool_name(tool: String) -> String:
	match tool:
		"wall": return "Wall"
		"outline": return "Outline"
		"research_table": return "Table"
		"chest": return "Chest"
		"bed": return "Bed"
		"chair": return "Chair"
		"campfire": return "Fire"
		"dig": return "Dig"
		"fill": return "Fill"
		"clear": return "Clear"
		"till": return "Till"
		_: return tool


func _on_tool_pressed(i: int) -> void:
	select_tool(i)


## The same path a click takes, so a test exercises the real thing.
func select_tool(i: int) -> void:
	if i < 0 or i >= _tools.size():
		return
	_selected = i
	_apply_selection()
	tool_selected.emit(i)


func _apply_selection() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].add_theme_stylebox_override("normal",
			CozyUiTheme.button_style(i == _selected))


# ---------------------------------------------------------------- resources

## Rebuild the resource row from an inventory. Adding a material to the game
## adds it here with no change to this function.
func set_resources(counts: Dictionary) -> void:
	var ids: Array = counts.keys()
	ids.sort()

	for id in ids:
		if not _resource_labels.has(id):
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 3)
			var icon := TextureRect.new()
			icon.texture = CozyPixelArt.make_material_icon(id,
				CozyMaterials.get_def(id).get("color", Color.WEB_GRAY))
			icon.custom_minimum_size = Vector2(CozyUiTheme.ICON, CozyUiTheme.ICON)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			cell.add_child(icon)
			var l := _mk_label(CozyUiTheme.TEXT)
			cell.add_child(l)
			_resources_box.add_child(cell)
			_resource_labels[id] = l
		_resource_labels[id].text = "%d" % int(counts[id])


func resource_text(id: String) -> String:
	if not _resource_labels.has(id):
		return ""
	return _resource_labels[id].text


func resource_cell_count() -> int:
	return _resource_labels.size()


# ---------------------------------------------------------------- status

func set_mode(text: String, building: bool) -> void:
	if _mode_label:
		_mode_label.text = text
		_mode_label.add_theme_color_override("font_color",
			CozyUiTheme.ACCENT if building else CozyUiTheme.TEXT_STRONG)


func set_camera(text: String, free_look: bool) -> void:
	if _camera_label:
		_camera_label.text = text
		_camera_label.add_theme_color_override("font_color",
			CozyUiTheme.WARN if free_look else CozyUiTheme.TEXT_DIM)


func set_context(text: String) -> void:
	if _context_label:
		_context_label.text = text


## Feedback, with severity. `warn` is for refusals — the one message the player
## must not miss, because it explains why nothing happened.
func set_message(text: String, warn := false) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.add_theme_color_override("font_color",
		CozyUiTheme.WARN if warn else CozyUiTheme.OK)


# ---------------------------------------------------------------- queries

func tool_button_count() -> int:
	return _tool_buttons.size()


func selected_tool_index() -> int:
	return _selected


func panel_count() -> int:
	return _panel_count


func message_text() -> String:
	return _message_label.text if _message_label else ""


func mode_text() -> String:
	return _mode_label.text if _mode_label else ""


func context_text() -> String:
	return _context_label.text if _context_label else ""


## Rectangle of a tool button in viewport space — used by the touch layer later,
## and by the self-check to prove the buttons are actually on screen.
func tool_button_rect(i: int) -> Rect2:
	if i < 0 or i >= _tool_buttons.size():
		return Rect2()
	return Rect2(_tool_buttons[i].global_position, _tool_buttons[i].size)
