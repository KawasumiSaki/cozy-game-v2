class_name CozyPackPanel
extends PanelContainer
## What the PLAYER is carrying — the Inventory category, which has been named in
## the HUD's own table since before there was anything to put in it.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS, AND WHY IT IS NOT THE EQUIPMENT SCREEN
##
## The player could chop a tree, watch "Tree: wood x4" appear in a message line,
## and then have NO WAY TO SEE THE WOOD AGAIN. `hud.set_resources()` draws the
## VILLAGE's account — the numbers that pay for walls — and the player's own pack
## was written to and never read back. That is the "declared with no consumer"
## shape at the end of a loop that otherwise works, and it is invisible in every
## assertion because every assertion reads the state, not the screen.
##
## The design doc's section 37 describes a fuller screen — an item grid and an
## information pane — and that is NOT this, because NOTHING CAN PUT AN ITEM IN THE
## PLAYER'S HANDS YET. Monsters do not exist; no shop sells equipment; the loot
## roller's output goes to whoever rolls it. A grid of empty squares that can
## never fill is the same mistake one step further on, and it teaches the player
## that the panel is broken. The grid arrives with the first thing that fills it.
##
## ---------------------------------------------------------------------------
## LAYOUT
##
##   header     "Pack", and the COPPER TOTAL — the one number a player checks
##              most and the one that has to be visible without reading a list
##   rule
##   materials  one row per thing carried: name, then the count right-aligned
##              so a column of numbers can be compared at a glance
##   items      THE BAG, as a grid of the places it has — see below
##
## The rows CHANGE SET, unlike the resident panel's fixed skills — a material
## appears the first time it is picked up. So the rows are kept in a dictionary
## keyed by material id and added or removed as the set changes, and `refresh()`
## WRITES INTO labels it already has rather than rebuilding the list. Rebuilding
## would be a refresh that reads its own output, which is the bug the resident
## panel was born with.
##
## ---------------------------------------------------------------------------
## TWO KINDS OF THING, TWO SECTIONS, AND THEY ARE NOT THE SAME SHAPE
##
## A material is an id and a COUNT (`CozyInventory`), so it is a row: "Wood 12".
## An item is a PLACE (`CozyItemContainer`), so it is a grid of cells and the holes
## between them are information — the eight slot is empty and the ninth is not, and
## a list of what is carried cannot say that. The item grid arrived with the first
## thing that could fill it (2026-09-15); before that it would have been a grid of
## empty squares that could never fill, which teaches a player the panel is broken.

## Every cell fires this with the instance id, and `main.gd` decides what a
## right-click on an item means. The panel does not know about bags or bodies —
## it draws what it is handed, which is what makes it checkable.
signal item_action_requested(instance_id: String)

const WIDTH := 240

## ASCII, because this project ships no font file and the UI draws in Godot's
## default face — a glyph that face lacks renders as a tofu box.
const EMPTY_TEXT := "nothing yet - chop a tree"

const GRID_COLUMNS := 3

var _title: Label = null
var _purse: Label = null
var _rows_box: VBoxContainer = null
var _empty: Label = null
var _grid: GridContainer = null
var _bag_cells: Array = []

var _rows: Dictionary = {}      ## material id -> {name: Label, count: Label}
var _order: Array[String] = []  ## the ids currently drawn, in display order


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	_build()


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", CozyUiTheme.GAP)
	add_child(col)

	_title = _label(CozyUiTheme.ACCENT, CozyUiTheme.FONT_SIZE)
	_title.text = "Pack"
	col.add_child(_title)

	_purse = _label(CozyUiTheme.TEXT_STRONG, CozyUiTheme.FONT_SIZE_SMALL)
	col.add_child(_purse)

	col.add_child(_rule())

	var heading := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	heading.text = "MATERIALS"
	col.add_child(heading)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 1)
	col.add_child(_rows_box)

	# Shown INSTEAD of the list while the pack is empty, rather than beside it.
	# It names the verb as well as the state: "nothing" alone tells a player the
	# panel works and the game is empty, which is not what is true.
	_empty = _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	_empty.text = EMPTY_TEXT
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_empty)

	col.add_child(_rule())

	var item_heading := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	item_heading.text = "ITEMS"
	col.add_child(item_heading)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	col.add_child(_grid)

	var item_hint := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	item_hint.text = "right-click an item"
	col.add_child(item_hint)


# ---------------------------------------------------------------- refresh

## Pull the pack. Called each frame while the panel is open — a count that moved
## because something was bought is a count the player is looking at.
##
## Only what CHANGED is touched: a row for a material the player is still
## carrying is written into the label that already holds it.
func refresh(state: CozyPlayerState) -> void:
	if state == null:
		return
	var pack := state.pack

	# MONEY FIRST, and in the header rather than as one row among the rest. It is
	# the number the player came here to check.
	_purse.text = "%d %s" % [int(pack.count(CozyPrices.CURRENCY)),
		CozyMaterials.display_name(CozyPrices.CURRENCY)]

	# What is carried, in a fixed order: the material table's own order, then
	# anything the table does not know about. Sorted by NAME would reshuffle the
	# list the first time a new material arrived, which is a panel that moves
	# while you are reading it.
	var ids: Array[String] = []
	for id in CozyMaterials.MATERIALS:
		if _carried(pack, String(id)):
			ids.append(String(id))
	# ...then anything the material table has never heard of. A pack can hold an
	# id this table does not have — a save from a later version, most likely — and
	# dropping it silently would hide the player's goods.
	#
	# THE SAME `_carried` RULE DECIDES BOTH LOOPS. The first version of this asked
	# the second one a raw `count(id) > 0` and put COPPER back in the list, one
	# line under a comment explaining why it is not a row — which the panel check
	# caught by name. Two loops, one rule.
	for id in pack.items:
		if not CozyMaterials.MATERIALS.has(String(id)) and _carried(pack, String(id)):
			ids.append(String(id))

	for id in ids:
		if not _rows.has(id):
			_add_row(id)
		# A row is only ever written from the STATE, never from the label it
		# wrote last frame.
		var row: Dictionary = _rows[id]
		(row["count"] as Label).text = "%d" % int(pack.count(id))
	for id in _rows.keys():
		if not ids.has(String(id)):
			_remove_row(String(id))

	_order = ids
	# BOTH SECTIONS, or the panel says "nothing yet" over a bag with a sword in it.
	_empty.visible = ids.is_empty() and state.bag.is_empty()

	# THE GRID IS AS BIG AS THE BAG. A backpack that grants more places has to grant
	# more cells, so this rebuilds when the capacity moves and only then — and the
	# comparison is against the STATE rather than against the cells that are already
	# there, so it settles instead of oscillating.
	if _bag_cells.size() != state.bag.capacity:
		_rebuild_grid(state.bag.capacity)
	for i in _bag_cells.size():
		(_bag_cells[i] as CozyItemSlot).show_item(state.bag.item_at(i))


## Rebuild the item grid, and ONLY the grid: the material rows above are written
## into labels that already exist, and a rebuild of the whole panel would be a
## refresh that reads its own output one level up.
func _rebuild_grid(places: int) -> void:
	for cell in _bag_cells:
		if is_instance_valid(cell):
			_grid.remove_child(cell)
			cell.queue_free()
	_bag_cells.clear()
	for i in places:
		var cell := CozyItemSlot.new()
		cell.right_clicked.connect(_on_cell_clicked)
		_grid.add_child(cell)
		_bag_cells.append(cell)


func _on_cell_clicked(instance_id: String) -> void:
	item_action_requested.emit(instance_id)


## Carried means MORE THAN ZERO, and money is not in the list.
##
## A material at zero is not "carried" — it is a row that costs the player a
## glance to learn nothing — and copper has the header, where it is read without
## scanning four rows to find it.
func _carried(pack: CozyInventory, id: String) -> bool:
	if id == CozyPrices.CURRENCY:
		return false
	return pack.count(id) > 0.0


func _add_row(id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	name_label.text = CozyMaterials.display_name(id)
	name_label.custom_minimum_size = Vector2(WIDTH - 60, 0)
	var count_label := _label(CozyUiTheme.TEXT, CozyUiTheme.FONT_SIZE_SMALL)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(count_label)
	_rows_box.add_child(row)
	_rows[id] = {"name": name_label, "count": count_label, "row": row}


func _remove_row(id: String) -> void:
	var row: Dictionary = _rows[id]
	(row["row"] as Node).queue_free()
	_rows.erase(id)


# ---------------------------------------------------------------- read back

## What is on screen, for the self-check.
##
## READ OFF THE WIDGETS, not off the state that was pushed in: a check that asked
## the pack what it holds would pass just as well against a panel that draws
## nothing at all. `row_ids()` is the drawn rows, in the order they appear.

func row_ids() -> Array[String]:
	return _order.duplicate()


## The count DRAWN against a material, or -1 when there is no row for it. -1
## rather than 0, because "the panel says zero" and "the panel says nothing" are
## different failures and a check has to be able to name which one it found.
func shown_count(id: String) -> int:
	if not _rows.has(id):
		return -1
	return int(((_rows[id] as Dictionary)["count"] as Label).text)


func purse_text() -> String:
	return _purse.text if _purse != null else ""


func empty_shown() -> bool:
	return _empty != null and _empty.visible


func row_count() -> int:
	return _rows.size()


# ---------------------------------------------------------------- the bag

## How many item cells are DRAWN. The bag's own capacity, not a number kept here —
## a panel that drew twelve cells for a sixteen-place pack would hide four places.
func bag_cell_count() -> int:
	return _bag_cells.size()


## The name drawn in one bag cell, or "" for a hole.
func bag_shown(index: int) -> String:
	if index < 0 or index >= _bag_cells.size():
		return ""
	return (_bag_cells[index] as CozyItemSlot).shown_name()


## The name drawn against an instance, wherever it sits in the bag, or "".
func bag_shown_anywhere(instance_id: String) -> String:
	for cell in _bag_cells:
		var c: CozyItemSlot = cell
		if c.has_item() and c.item().instance_id == instance_id:
			return c.shown_name()
	return ""


func bag_empty_cells() -> int:
	var n := 0
	for cell in _bag_cells:
		if not (cell as CozyItemSlot).has_item():
			n += 1
	return n


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
