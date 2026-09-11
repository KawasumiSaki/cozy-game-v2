class_name CozyBuildability
extends RefCounted
## How ready a patch of ground is to carry a building (V2.1 doc #11).
##
## The doc is explicit that this cannot be a boolean:
##
##     NATURAL -> CLEARED -> PREPARED -> BUILDABLE
##
## with RESTRICTED for ground that will never take a building (water, cliff)
## and OCCUPIED for ground that already carries one.
##
## Keeping the intermediate states matters because they are the steps the player
## actually performs — clearing a lawn is a distinct act from preparing a
## foundation, and the UI needs to say which one is missing.

const NATURAL := 0     ## Untouched ground.
const CLEARED := 1     ## Vegetation removed; still not levelled.
const PREPARED := 2    ## Levelled and consolidated.
const BUILDABLE := 3   ## Ready for a foundation.
const RESTRICTED := 4  ## Can never be built on (water, cliff face).
const OCCUPIED := 5    ## A building already stands here.

const NAMES := {
	NATURAL: "natural",
	CLEARED: "cleared",
	PREPARED: "prepared",
	BUILDABLE: "buildable",
	RESTRICTED: "restricted",
	OCCUPIED: "occupied",
}


static func name_of(v: int) -> String:
	return NAMES.get(v, "unknown")


## May a foundation be placed here? OCCUPIED is excluded — something is already
## there; the caller must clear it first.
static func accepts_building(v: int) -> bool:
	return v == BUILDABLE or v == PREPARED


static func from_name(n: String) -> int:
	for k in NAMES:
		if NAMES[k] == n:
			return k
	return NATURAL
