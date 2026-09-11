class_name CozyNpcPanel
extends PanelContainer
## The resident panel — what a right-click on a person opens.
##
## It exists because V2-22 and V2-25 filled `CozyNpcState` with things worth
## looking at (attributes, ten skills, passions, traits, a decaying set of needs
## and a daily schedule) and none of it was reachable. Data nobody can see is
## data nobody can act on.
##
## LAYOUT, and the reasoning behind each choice:
##
##   header      name, job, and what they are doing RIGHT NOW
##   needs       BARS, not numbers — these are levels that move, and a bar
##               answers "how much is left" at a glance where a number does not
##   attributes  a compact grid; they change rarely and only need reading
##   skills      value plus a passion marker rather than a second column, so the
##               row stays short enough to scan
##   schedule    the doc's own day (#114) with the current block marked
##
## Relations is deliberately ABSENT. There is no social system to draw from, and
## a page that is always empty teaches the player that the panel is broken.
##
## Everything here READS state. The panel never mutates a resident.

const WIDTH := 268

## The current-schedule-block marker.
##
## ASCII on purpose: this project ships no font file, so the UI draws in Godot's
## default face. A glyph that face lacks renders as a tofu box, and the previous
## "▶" was exactly that risk — no one had seen it because nothing instantiated
## this panel.
const MARK_HERE := ">"
const MARK_NONE := " "

var _title: Label = null
var _subtitle: Label = null
var _needs_box: VBoxContainer = null
var _attrs: Label = null
var _skills_box: VBoxContainer = null
var _schedule_box: VBoxContainer = null

var _meters: Dictionary = {}       ## need id -> {fill: ColorRect, value: Label}
var _skill_rows: Dictionary = {}   ## skill id -> Label
var _schedule_rows: Array = []     ## [{label: Label, hour: int, name: String}]


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", CozyUiTheme.panel_style())
	_build()


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", CozyUiTheme.GAP)
	add_child(col)

	_title = _label(CozyUiTheme.ACCENT, CozyUiTheme.FONT_SIZE)
	_subtitle = _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	col.add_child(_title)
	col.add_child(_subtitle)
	col.add_child(_rule())

	# ---- needs ----
	col.add_child(_heading("NEEDS"))
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 2)
	col.add_child(_needs_box)
	for spec in [["hunger", "Hunger", CozyUiTheme.WARN],
			["energy", "Energy", CozyUiTheme.ACCENT],
			["mood", "Mood", CozyUiTheme.OK]]:
		_needs_box.add_child(_make_meter(String(spec[0]), String(spec[1]), spec[2]))

	# ---- attributes ----
	col.add_child(_rule())
	col.add_child(_heading("ATTRIBUTES"))
	_attrs = _label(CozyUiTheme.TEXT, CozyUiTheme.FONT_SIZE_SMALL)
	_attrs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_attrs)

	# ---- skills ----
	col.add_child(_rule())
	col.add_child(_heading("SKILLS"))
	_skills_box = VBoxContainer.new()
	_skills_box.add_theme_constant_override("separation", 1)
	col.add_child(_skills_box)
	for id in CozySkills.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_label := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
		name_label.text = CozySkills.display_name(id)
		name_label.custom_minimum_size = Vector2(78, 0)
		var value_label := _label(CozyUiTheme.TEXT, CozyUiTheme.FONT_SIZE_SMALL)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(value_label)
		_skills_box.add_child(row)
		_skill_rows[id] = value_label

	# ---- schedule ----
	col.add_child(_rule())
	col.add_child(_heading("SCHEDULE"))
	_schedule_box = VBoxContainer.new()
	_schedule_box.add_theme_constant_override("separation", 1)
	col.add_child(_schedule_box)
	# The activity NAME is captured here and never read back off the label.
	# refresh() runs every frame; a refresh that re-derives its own input from its
	# own output corrupts the text a little more each frame. That is not a
	# hypothetical — it is the bug this panel was born with, and the reason
	# _check_npc_panel asserts idempotence rather than just "it drew something".
	for block in CozySchedule.DEFAULT_DAY:
		var hour := int(block["hour"])
		var what := CozySchedule.activity_name(String(block["activity"]))
		var l := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
		l.text = _schedule_text(MARK_NONE, hour, what)
		_schedule_box.add_child(l)
		_schedule_rows.append({"label": l, "hour": hour, "name": what})


# ---------------------------------------------------------------- refresh

## Pull everything from the resident's state. Called each frame while the panel
## is open, because needs MOVE — a panel showing a stale hunger value is worse
## than no panel.
func refresh(st: CozyNpcState, hour: float, activity: String) -> void:
	if st == null:
		return

	_title.text = st.display_name
	_subtitle.text = "%s  -  %s" % [st.job_name(), CozySchedule.activity_name(activity)]

	_set_meter("hunger", st.hunger)
	_set_meter("energy", st.energy)
	_set_meter("mood", st.mood)

	_attrs.text = "HP %d/%d    Speed %.1f\nAttack %.1f    Defence %.1f    Luck %.1f" % [
		int(st.hp), int(st.hp_max), st.effective_move_speed(),
		st.attack_speed, st.defense, st.luck]

	for id in CozySkills.ORDER:
		var passion := st.passion(id)
		# A marker rather than a column: at this width a second column costs
		# more room than the information is worth.
		var mark := ""
		match passion:
			CozySkills.Passion.PASSIONATE:
				mark = "  ##"
			CozySkills.Passion.INTERESTED:
				mark = "  #"
			CozySkills.Passion.HATE:
				mark = "  x"
		_skill_rows[id].text = "%d%s" % [st.skill(id), mark]

	# Highlight the block the day is currently in.
	var current_hour := -1
	for block in CozySchedule.DEFAULT_DAY:
		if hour >= float(block["hour"]):
			current_hour = int(block["hour"])
	for row in _schedule_rows:
		var here: bool = int(row["hour"]) == current_hour
		var l: Label = row["label"]
		l.add_theme_color_override("font_color",
			CozyUiTheme.ACCENT if here else CozyUiTheme.TEXT_DIM)
		# Rebuilt from the stored name, so calling this a thousand times gives the
		# same string as calling it once.
		l.text = _schedule_text(MARK_HERE if here else MARK_NONE,
			int(row["hour"]), String(row["name"]))


## The one place that knows how a schedule row reads.
##
## Build and refresh both need this string, and when they each formatted it
## themselves they could drift apart — which is the same family of bug as the
## substr() this panel was born with. One formatter, two callers.
static func _schedule_text(mark: String, hour: int, what: String) -> String:
	return "%s %02d:00  %s" % [mark, hour, what]


# ---------------------------------------------------------------- pieces

func _make_meter(id: String, caption: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	name_label.text = caption
	name_label.custom_minimum_size = Vector2(52, 0)
	row.add_child(name_label)

	# A meter is a track with a fill. The fill's width is the value, so the
	# shape carries the information and the number only confirms it.
	var track := Panel.new()
	track.custom_minimum_size = Vector2(120, 10)
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.08, 0.07, 0.09, 1.0)
	track_style.set_border_width_all(1)
	track_style.border_color = CozyUiTheme.PANEL_BORDER_DIM
	track_style.set_corner_radius_all(0)
	track.add_theme_stylebox_override("panel", track_style)
	row.add_child(track)

	var fill := ColorRect.new()
	fill.color = colour
	fill.position = Vector2(1, 1)
	fill.size = Vector2(118, 8)
	track.add_child(fill)

	var value := _label(CozyUiTheme.TEXT, CozyUiTheme.FONT_SIZE_SMALL)
	value.custom_minimum_size = Vector2(30, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	_meters[id] = {"fill": fill, "value": value}
	return row


func _set_meter(id: String, v: float) -> void:
	if not _meters.has(id):
		return
	var m: Dictionary = _meters[id]
	var frac := clampf(v / 100.0, 0.0, 1.0)
	var fill: ColorRect = m["fill"]
	fill.size = Vector2(118.0 * frac, 8)
	var value: Label = m["value"]
	value.text = "%d" % int(v)


func _heading(text: String) -> Label:
	var l := _label(CozyUiTheme.TEXT_DIM, CozyUiTheme.FONT_SIZE_SMALL)
	l.text = text
	return l


func _label(colour: Color, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = CozyUiTheme.PANEL_BORDER_DIM
	r.custom_minimum_size = Vector2(0, 1)
	return r


# ---------------------------------------------------------------- queries

func title_text() -> String:
	return _title.text if _title else ""


func subtitle_text() -> String:
	return _subtitle.text if _subtitle else ""


func attrs_text() -> String:
	return _attrs.text if _attrs else ""


func meter_value(id: String) -> int:
	if not _meters.has(id):
		return -1
	return int((_meters[id]["value"] as Label).text)


func meter_fraction(id: String) -> float:
	if not _meters.has(id):
		return -1.0
	return (_meters[id]["fill"] as ColorRect).size.x / 118.0


func skill_text(id: String) -> String:
	return (_skill_rows[id] as Label).text if _skill_rows.has(id) else ""


func skill_row_count() -> int:
	return _skill_rows.size()


func schedule_row_count() -> int:
	return _schedule_rows.size()


## The rendered text of one schedule row, for assertions.
func schedule_line(hour: int) -> String:
	for row in _schedule_rows:
		if int(row["hour"]) == hour:
			return (row["label"] as Label).text
	return ""


## Which schedule row is currently marked — the panel's "where am I in the day".
func highlighted_schedule_hour() -> int:
	for row in _schedule_rows:
		if (row["label"] as Label).text.begins_with(MARK_HERE):
			return int(row["hour"])
	return -1
