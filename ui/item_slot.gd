class_name CozyItemSlot
extends Panel
## One place in a bag or on a body: the item in it, or the hole where one goes.
##
## ---------------------------------------------------------------------------
## A CELL IS A POSITION, NOT A COUNT
##
## `CozyItemContainer` and `CozyEquipment` both keep an ARRAY of places, and both
## say why: the second ring goes in the second place, and a sparse list would put
## both rings back in the first. So a panel that drew only the items it happened to
## have — and not the places they are NOT in — could not show which cell is free,
## which is the one thing a grid exists to say. Every cell is drawn whether or not
## there is anything in it.
##
## ---------------------------------------------------------------------------
## RIGHT-CLICK, AND IT ACCEPTS THE EVENT
##
## Right-click is already the world's "what is this" gesture. Inside a panel there
## is no world to ask about, so a right-click on a cell means "what can I do with
## this one" — and the event is ACCEPTED, because a click that carried on into
## `_unhandled_input` would open the world menu behind the panel as well, and one
## click would produce two menus.
##
## LEFT-CLICK DOES NOTHING, deliberately. There is no drag yet, so a cell that
## reacted to a left-click would be a button that appears to do something; the
## verbs live in one place, and that place is the menu.

signal right_clicked(instance_id: String)

## How big a cell is.
##
## WIDE ENOUGH FOR A NAME, which is the whole of what a cell can show: this project
## ships no item icons, and a square of flat colour would be a hole that says
## nothing at all. `clip_text` is on, so a long name is cut rather than overflowing
## into its neighbour, and the FULL name is in the tooltip.
const SIZE := Vector2(68, 22)

## How wide the picture is. A 16 px sprite shown at 16 px, on a 22 px cell — the
## one size at which a pixel sprite is exactly itself (see `ART_PROFILE` §4).
const ICON := 16

var _item: CozyItemInstance = null
var _name: Label = null
## The picture, when there is one. HIDDEN rather than absent for anything with
## no icon, so the cell keeps its shape and the name starts in the same place.
var _icon: TextureRect = null


func _ready() -> void:
	custom_minimum_size = SIZE
	# STOP, so a click on a cell lands on the cell rather than on whatever the panel
	# happens to be covering.
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CozyUiTheme.slot_style(false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 2
	row.offset_right = -3

	# THE ICON IS SMALLER THAN THE CELL AND SITS AT ITS LEFT. A 16 px sprite scaled
	# to fill a 22 px cell would be blurry at any other scale, and the name is what
	# tells a player which of two iron swords this is — the picture only has to say
	# what KIND of thing it is.
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(ICON, 0)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", CozyUiTheme.FONT_SIZE_SMALL)
	_name.add_theme_color_override("font_color", CozyUiTheme.TEXT)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# And the label does not eat the click that is meant for the cell underneath it.
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_name)

	show_item(null)


## Show an item, or nothing.
##
## `null` IS A HOLE rather than an absence: the cell stays, the same size, and is
## visibly empty. That is the difference between a bag with room in it and a bag
## that has lost a cell.
func show_item(item: CozyItemInstance) -> void:
	_item = item
	if item == null:
		_name.text = ""
		_icon.texture = null
		_icon.visible = false
		tooltip_text = ""
		add_theme_stylebox_override("panel", CozyUiTheme.slot_style(false))
		return
	# WHAT IT LOOKS LIKE, which for a glamoured item is not what it is. This is the
	# rule `CozyItemInstance.appearance_name()` was written for and, until this
	# existed, had no consumer: a cell showing "Iron Sword" over a steel sword
	# would be a bug report about a lie, and the tooltip is where the truth lives.
	_name.text = item.appearance_name()
	# BY THE DEFINITION, not by the instance: two iron swords are two swords and they
	# are the same PICTURE. `appearance_id()` rather than `definition_id`, so a
	# glamoured item wears the icon of what it looks like — the same rule the name
	# above already follows.
	_icon.texture = CozyItemIcons.icon_for(item.appearance_id())
	# HIDDEN, not merely empty: an empty TextureRect still takes its 16 px, and the
	# name would start in a different place on a cell with no picture — so a bag of
	# mixed icons would have a ragged left edge for no reason.
	_icon.visible = _icon.texture != null
	tooltip_text = item.describe()
	add_theme_stylebox_override("panel", CozyUiTheme.slot_style(true))


func item() -> CozyItemInstance:
	return _item


func has_item() -> bool:
	return _item != null


## What the cell is SHOWING, for the self-check.
##
## Read off the WIDGET, not off the item it was handed: a check that asked the item
## what it was called would pass just as well against a cell that drew nothing, and
## the whole question about a panel is what reached the screen.
func shown_name() -> String:
	return _name.text if _name != null else ""


func _gui_input(event: InputEvent) -> void:
	if _item == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		right_clicked.emit(_item.instance_id)
