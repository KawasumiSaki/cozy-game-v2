class_name CozyVfxDefs
extends RefCounted
## Data-driven VFX definitions (V2.1 doc E.18 / 58.3 Layer 4).
##
## VFX are pixel sprites like everything else outside the building system, and
## they go through the same Art Grammar as the rest of the world — doc E.14 is
## explicit that a campfire, a stream and a magic circle must read as belonging
## to the same game rather than to three different ones.
##
## A definition says how many frames, how fast, how big, and how high the effect
## sits above its anchor. Adding weather later is a row here.

const VFX := {
	"fire": {
		"frames": 4,
		"frame_time": 0.10,
		"size": 0.55,
		"height": 0.30,     ## Metres above the anchor.
		"additive": false,
	},
	"smoke": {
		"frames": 4,
		"frame_time": 0.19,
		"size": 0.75,
		"height": 1.05,
		"additive": false,
	},
	"magic": {
		"frames": 4,
		"frame_time": 0.14,
		"size": 0.9,
		"height": 0.8,
		"additive": true,
	},
}

const DEFAULT := "fire"


static func get_def(id: String) -> Dictionary:
	return VFX.get(id, VFX[DEFAULT])


static func exists(id: String) -> bool:
	return VFX.has(id)
