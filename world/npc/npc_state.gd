class_name CozyNpcState
extends RefCounted
## A resident's data (V2.1 doc #43).
##
## This is STATE, not a node — the same rule the building system follows. What a
## resident IS lives here; the node that walks them around reads it. That is what
## makes a save file possible later (V2-26) without serialising a scene tree.
##
##     NPC
##     ├── identity
##     ├── attributes
##     ├── skills        (10, 0..20, 愿景 §9)
##     ├── passions      (4 tiers, 愿景 §10)
##     ├── traits        (1..3, drawn deterministically)
##     ├── inventory
##     └── job           (responsibility, not current action — doc #44)
##
## It deliberately does NOT hold a schedule or decaying needs. Those are V2-25,
## and putting them in before the systems that read them exist would be guessing
## at their shape.

var id := ""
var display_name := "Resident"
var job_id := "researcher"

# ---------------------------------------------------------------- attributes
# 愿景 §9. Ranges are documented here rather than enforced everywhere, except
# where a value out of range would silently skew a calculation.

var hp := 100.0
var hp_max := 100.0
var hunger := 0.0        ## 0 = fed, 100 = starving
var energy := 100.0      ## 0 = exhausted, 100 = rested
var mood := 75.0         ## 0..100
var move_speed := 3.5
var attack_speed := 1.0
var defense := 0.0
var luck := 0.0

var skills: Dictionary = {}     ## skill id -> int, 0..20
var passions: Dictionary = {}   ## skill id -> CozySkills.Passion
var traits: Array[String] = []
var inventory: CozyInventory = null

## Deterministic seed for this resident (doc E.21).
var seed_val := 0


static func create(p_id: String, p_name: String, p_job := "researcher",
		p_seed := 0) -> CozyNpcState:
	var s := CozyNpcState.new()
	s.id = p_id
	s.display_name = p_name
	s.job_id = p_job
	s.seed_val = p_seed if p_seed != 0 else hash(p_id)
	s.skills = CozySkills.blank_skills()
	s.passions = CozySkills.blank_passions()
	s.inventory = CozyInventory.new()
	s.traits = CozyTraitDefs.roll(s.seed_val)
	return s


# ---------------------------------------------------------------- skills

func skill(id: String) -> int:
	return int(skills.get(id, 0))


## Raise a skill, clamped to the documented range (愿景 §9: 0~20).
func train(id: String, amount := 1) -> void:
	if not CozySkills.exists(id):
		return
	skills[id] = CozySkills.clamp_level(skill(id) + amount)


func passion(id: String) -> int:
	return int(passions.get(id, CozySkills.Passion.NEUTRAL))


func set_passion(id: String, p: int) -> void:
	if CozySkills.exists(id):
		passions[id] = p


## Experience multiplier for working at a skill (愿景 §10).
func passion_multiplier(id: String) -> float:
	return CozySkills.passion_multiplier(passion(id))


## The doc's rule that aversion means the work cannot be assigned.
func can_be_assigned_to(skill_id: String) -> bool:
	return CozySkills.can_be_assigned(passion(skill_id))


# ---------------------------------------------------------------- traits

func has_trait(id: String) -> bool:
	return traits.has(id)


## Sum of a modifier key across every trait held. Unknown keys return 0, which
## makes an authored-but-unimplemented trait inert rather than an error.
func modifier_sum(key: String) -> float:
	var total := 0.0
	for t in traits:
		total += float(CozyTraitDefs.modifiers(t).get(key, 0.0))
	return total


func modifier_product(key: String) -> float:
	var out := 1.0
	for t in traits:
		# Multiplicative modifiers are authored as "at least 1.0", so a trait
		# that does not mention the key must multiply by 1 rather than by 0.
		var m: float = float(CozyTraitDefs.modifiers(t).get(key, 1.0))
		if m > 0.0:
			out *= m
	return out


## Effective walking speed: base, scaled by traits.
func effective_move_speed() -> float:
	return move_speed * modifier_product("move_speed")


## Effective working speed: the job's own multiplier, then traits on top.
##
## Passion scales EXPERIENCE in the doc, not speed, so it is deliberately absent
## here — conflating the two would quietly make a passionate worker faster rather
## than better.
func effective_work_speed() -> float:
	return modifier_product("work_speed")


# ---------------------------------------------------------------- job

func job_name() -> String:
	return CozyJobDefs.display_name(job_id)


func job_point_type() -> String:
	return CozyJobDefs.point_type(job_id)


## Is this resident allowed to do their job at all? Doc §10: an aversion means
## "无法主动安排" — not assignable.
func is_assignable() -> bool:
	var s := CozyJobDefs.primary_skill(job_id)
	return s == "" or can_be_assigned_to(s)


# ---------------------------------------------------------------- serialise

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"job": job_id,
		"seed": seed_val,
		"hp": hp,
		"hp_max": hp_max,
		"hunger": hunger,
		"energy": energy,
		"mood": mood,
		"move_speed": move_speed,
		"attack_speed": attack_speed,
		"defense": defense,
		"luck": luck,
		"skills": skills.duplicate(),
		"passions": passions.duplicate(),
		"traits": traits.duplicate(),
		"inventory": inventory.items.duplicate() if inventory else {},
	}


static func from_dict(d: Dictionary) -> CozyNpcState:
	var s := CozyNpcState.create(String(d.get("id", "")), String(d.get("name", "")),
		String(d.get("job", "researcher")), int(d.get("seed", 0)))
	s.hp = float(d.get("hp", 100.0))
	s.hp_max = float(d.get("hp_max", 100.0))
	s.hunger = float(d.get("hunger", 0.0))
	s.energy = float(d.get("energy", 100.0))
	s.mood = float(d.get("mood", 75.0))
	s.move_speed = float(d.get("move_speed", 3.5))
	s.attack_speed = float(d.get("attack_speed", 1.0))
	s.defense = float(d.get("defense", 0.0))
	s.luck = float(d.get("luck", 0.0))

	s.skills = CozySkills.blank_skills()
	for k in d.get("skills", {}):
		s.skills[k] = CozySkills.clamp_level(int(d["skills"][k]))
	s.passions = CozySkills.blank_passions()
	for k in d.get("passions", {}):
		s.passions[k] = int(d["passions"][k])

	s.traits.clear()
	for t in d.get("traits", []):
		s.traits.append(String(t))

	if s.inventory == null:
		s.inventory = CozyInventory.new()
	for k in d.get("inventory", {}):
		s.inventory.add(String(k), float(d["inventory"][k]))
	return s


## One line for the HUD, so a resident's character is legible at a glance.
func describe() -> String:
	var top := ""
	var best := -1
	for id in CozySkills.ORDER:
		if skill(id) > best:
			best = skill(id)
			top = id
	return "%s · %s · %s %d · %d trait(s)" % [
		display_name, job_name(), top, best, traits.size()]
