class_name CozyGearPanel
extends PanelContainer
## What the player is WEARING, as the thirteen places a body has.
##
## ---------------------------------------------------------------------------
## THIRTEEN CELLS, AND THE COUNT COMES FROM THE BODY
##
## Willow, 2026-09-15: helmet / chest / legs / arms / boots / backpack / THREE
## charms / TWO rings / weapon / off hand. Ten KINDS and thirteen PLACES, and the
## difference is the whole reason this panel is drawn from `capacity_of()` rather
## than from a count of what happens to be worn — a row of one ring is a row of one
## ring whether the body has two ring places or ten, and the panel would be unable
## to show the second place filling up.
##
## `CozyEquipment` already owns both numbers (`capacity` and `filled`), so nothing
## here counts anything.
##
## ---------------------------------------------------------------------------
## WHY THE NUMBERS ARE ON IT
##
## A panel of thirteen empty boxes is a diagram. What makes it an equipment screen
## is that putting the sword on moves a number, so the two numbers a fight is made
## of are at the top — and they are read from `CozyPlayerState`, which reads
## `CozyStats`, which is the only place the four passes are implemented. Nothing
## here adds anything up.

const WIDTH := 300

## The label column, sized so the widest row — three charm cells — still fits
## inside `WIDTH`. WIDER THAN IT LOOKS LIKE IT NEEDS TO BE, because the three-cell
## row is the one that decides and it is not the first row on the panel.
const NAME_COL := 62

const EMPTY_TEXT := "nothing worn - the brigand is carrying a sword"

var _rows: Dictionary = {}      ## kind -> Array[CozyItemSlot], one per place
var _order: Array[String] = []  ## the kinds, in the order they are drawn
var _stats: Label = null

signal item_action_requested(instance_id: String)


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	_build()


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", CozyUiTheme.GAP)
	add_child(col)

	var title := _label(CozyUiTheme.ACCENT, CozyUiTheme.FONT_SIZE)
	title.text = "Gear"
	col.add_child(title)

	_stats = _label(CozyUiTheme.TEXT_STRONG, CozyUiTheme.FONT_SIZE_SMALL)
	col.add_child(_stats)

	col.add_child(_rule())

	var heading := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	heading.text = "WORN"
	col.add_child(heading)

	# ONE ROW PER KIND, in `CozyItemDefs.SLOTS` order — which `data/items.gd` says
	# is "the order a panel draws it", so the two cannot drift.
	for kind in CozyItemDefs.SLOTS:
		col.add_child(_make_row(String(kind)))

	var hint := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	hint.text = "right-click a worn item"
	col.add_child(hint)


func _make_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	name_label.text = CozyItemDefs.slot_name(kind)
	name_label.custom_minimum_size = Vector2(NAME_COL, 0)
	row.add_child(name_label)

	var cells: Array = []
	for i in CozyItemDefs.capacity_of(kind):
		var cell := CozyItemSlot.new()
		cell.right_clicked.connect(_on_cell_clicked)
		row.add_child(cell)
		cells.append(cell)
	_rows[kind] = cells
	_order.append(kind)
	return row


# ---------------------------------------------------------------- refresh

## Pull what is worn. Called each frame while the panel is open — putting a sword
## on is a change the player is looking at.
##
## WRITES INTO CELLS IT ALREADY HAS. The thirteen places are built once and the
## refresh fills them, because a refresh that rebuilt the row it was reading is the
## bug the resident panel was born with.
func refresh(state: CozyPlayerState) -> void:
	if state == null:
		return
	var eq := state.equipment
	for kind in _order:
		var cells: Array = _rows[kind]
		for i in cells.size():
			(cells[i] as CozyItemSlot).show_item(eq.worn(kind, i))
	# From the state, never from the labels this wrote last frame.
	_stats.text = "Attack %d    HP %d" % [
		int(round(state.attack())), int(round(state.max_hp()))]


func _on_cell_clicked(instance_id: String) -> void:
	item_action_requested.emit(instance_id)


# ---------------------------------------------------------------- read back

## What is on screen, for the self-check.
##
## READ OFF THE WIDGETS, not off the equipment that was pushed in: a check that
## asked `CozyEquipment` what was worn would pass just as well against a panel that
## draws nothing at all. That is the same rule the pack panel's read-backs follow,
## and it is the only rule that makes a panel checkable.

func cell_count() -> int:
	var n := 0
	for kind in _order:
		n += (_rows[kind] as Array).size()
	return n


func cells_of(kind: String) -> int:
	return (_rows.get(kind, []) as Array).size()


## How many cells are drawn EMPTY, which is the thing a grid exists to show.
func empty_cells() -> int:
	var n := 0
	for kind in _order:
		for cell in _rows[kind]:
			if not (cell as CozyItemSlot).has_item():
				n += 1
	return n


## The name drawn in one place, or "" for a hole.
func shown_in(kind: String, index: int) -> String:
	var cells: Array = _rows.get(kind, [])
	if index < 0 or index >= cells.size():
		return ""
	return (cells[index] as CozyItemSlot).shown_name()


## The name drawn against an instance, wherever it is worn, or "". For a check
## that knows WHICH item it put on but not which place the body chose.
func shown_anywhere(instance_id: String) -> String:
	for kind in _order:
		for cell in _rows[kind]:
			var c: CozyItemSlot = cell
			if c.has_item() and c.item().instance_id == instance_id:
				return c.shown_name()
	return ""


func stats_text() -> String:
	return _stats.text if _stats != null else ""


func worn_shown() -> bool:
	return empty_cells() < cell_count()


# ---------------------------------------------------------------- widgets

func _label(c: Color, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = CozyUiTheme.PANEL_BORDER_DIM
	r.custom_minimum_size = Vector2(0, 1)
	return r
