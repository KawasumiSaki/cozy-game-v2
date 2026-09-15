class_name CozyUiTheme
extends RefCounted
## UI design tokens, as data.
##
## Everything visual in the interface reads from here, so the HUD is one palette
## change away from a different mood. Same principle the rest of the project
## uses for materials and objects.
##
## DIRECTION (deliberate, not default):
## The game is a warm pixel-art world, so the interface is a PIXEL panel —
## waxy parchment-and-ink, hard 1px edges, no rounded corners, no gradients, no
## drop shadows, no blur. Anything soft would read as a different game layered
## on top. Borders are drawn rather than shaded because a pixel panel is a
## drawn thing.
##
## Colour is warm-neutral rather than pure grey or pure black: pure black next
## to a bright pastoral scene reads as a hole, and pure grey reads as a
## spreadsheet.
##
## Nothing here is decorative. Every colour and every pixel of spacing carries
## either information or separation. That is the whole budget.

# ---------------------------------------------------------------- colour

const PANEL_BG := Color(0.13, 0.11, 0.15, 0.90)      ## Warm near-black, warm enough to sit on grass
const PANEL_BG_SOLID := Color(0.13, 0.11, 0.15, 1.0)
const PANEL_BORDER := Color(0.66, 0.60, 0.47, 1.0)    ## Parchment edge
const PANEL_BORDER_DIM := Color(0.38, 0.35, 0.31, 1.0)

const TEXT := Color(0.95, 0.93, 0.87, 1.0)            ## Warm white, never #fff
const TEXT_DIM := Color(0.66, 0.62, 0.55, 1.0)
const TEXT_STRONG := Color(1.0, 0.97, 0.88, 1.0)

const ACCENT := Color(0.87, 0.72, 0.38, 1.0)          ## Selected / active — warm gold
const ACCENT_DIM := Color(0.52, 0.44, 0.26, 1.0)
const WARN := Color(0.88, 0.47, 0.36, 1.0)            ## Refusals
const OK := Color(0.62, 0.78, 0.46, 1.0)              ## Confirmations

# ---------------------------------------------------------------- metric
#
# A strict grid. Pixel art at this scale wants even numbers; odd offsets land
# on half-pixels once the window is scaled and the edge crawls.

const GRID := 4
const PAD := 8            ## Inner padding of a panel
const GAP := 6            ## Between siblings
const BORDER := 1         ## Border thickness, always 1px — a pixel panel is drawn
const BAR_H := 40         ## Height of the bottom bar
const STRIP_H := 24       ## Height of the top strip
const ICON := 16          ## Icon size in UI pixels

const FONT_SIZE := 12
const FONT_SIZE_SMALL := 10


## A panel: dark fill, 1px parchment edge, square corners.
static func panel_style(fill := PANEL_BG, border := PANEL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(PAD)
	return sb


## A button in its three states. The pressed/active state is FILLED with accent
## rather than merely outlined, so which tool is live is readable at a glance
## instead of needing to be hunted for.
static func button_style(active := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT_DIM if active else Color(0.20, 0.18, 0.22, 0.92)
	sb.border_color = ACCENT if active else PANEL_BORDER_DIM
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = PAD
	sb.content_margin_right = PAD
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func button_style_hover() -> StyleBoxFlat:
	var sb := button_style(false)
	sb.bg_color = Color(0.28, 0.25, 0.30, 0.95)
	sb.border_color = PANEL_BORDER
	return sb


## One place in a bag or on a body.
##
## EMPTY AND FILLED ARE DIFFERENT FILLS, not two weights of border. A hole in a
## bag is the thing a grid exists to show, and it has to be visible from across
## the panel rather than needing to be looked for — four cells in a row and one of
## them a lighter outline is a hole nobody finds.
static func slot_style(filled := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.21, 0.26, 0.95) if filled \
		else Color(0.11, 0.10, 0.13, 0.95)
	sb.border_color = ACCENT_DIM if filled else PANEL_BORDER_DIM
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(0)
	return sb


static func label_color(dim := false) -> Color:
	return TEXT_DIM if dim else TEXT
