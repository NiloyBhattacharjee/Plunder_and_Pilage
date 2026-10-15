class_name Dice
## Dice and checks, tabletop style: d20 + modifiers against a DC, or against another d20 roll.
## Every check keeps its breakdown, so the player can see exactly why it went the way it did.
## A natural 20 always succeeds (and crits); a natural 1 always fails (and fumbles).


## A skill or stat of 0-20 as a modifier, -5..+5, like an ability score.
static func mod(score: float) -> int:
	return int(floor((score - 10.0) / 2.0))


static func roll(rng: RandomNumberGenerator, n: int, die: int) -> int:
	var total := 0
	for i in n:
		total += rng.randi_range(1, die)
	return total


static func sum_parts(parts: Array) -> int:
	var total := 0
	for p in parts:
		total += int(p[1])
	return total


## parts: [[label, modifier], ...]. Returns {label, roll, mods, total, dc, success, crit, fumble, margin, parts}.
static func check(rng: RandomNumberGenerator, label: String, parts: Array, dc: int) -> Dictionary:
	var r := rng.randi_range(1, 20)
	var mods := sum_parts(parts)
	var total := r + mods
	var success := r == 20 or (r != 1 and total >= dc)
	return {"label": label, "roll": r, "mods": mods, "total": total, "dc": dc, "success": success,
		"crit": r == 20, "fumble": r == 1, "margin": total - dc, "parts": parts}


## Opposed roll: a against b. Ties go to a (the one acting). Natural 20 beats anything but another 20.
static func contest(rng: RandomNumberGenerator, label: String, parts_a: Array, parts_b: Array) -> Dictionary:
	var ra := rng.randi_range(1, 20)
	var rb := rng.randi_range(1, 20)
	var ta := ra + sum_parts(parts_a)
	var tb := rb + sum_parts(parts_b)
	var success: bool
	if ra == 20 and rb != 20: success = true
	elif rb == 20 and ra != 20: success = false
	elif ra == 1 and rb != 1: success = false
	else: success = ta >= tb
	return {"label": label, "roll": ra, "mods": sum_parts(parts_a), "total": ta, "dc": tb, "success": success,
		"crit": ra == 20, "fumble": ra == 1, "margin": ta - tb, "parts": parts_a,
		"opposed": {"roll": rb, "mods": sum_parts(parts_b), "parts": parts_b}}


## Chance that d20 + mods meets dc, natural 20s and 1s included.
static func chance(mods: int, dc: int) -> float:
	var wins := 0
	for r in range(1, 21):
		if r == 20 or (r != 1 and r + mods >= dc):
			wins += 1
	return wins / 20.0


static func contest_chance(mods_a: int, mods_b: int) -> float:
	var wins := 0
	for ra in range(1, 21):
		for rb in range(1, 21):
			if ra == 20 and rb != 20: wins += 1
			elif rb == 20 and ra != 20: pass
			elif ra == 1 and rb != 1: pass
			elif ra + mods_a >= rb + mods_b: wins += 1
	return wins / 400.0


## The roll written out for the battle log (BBCode for RichTextLabel).
static func describe(c: Dictionary) -> String:
	var lines := PackedStringArray()
	var bits := PackedStringArray(["d20 [b]%d[/b]" % c.roll])
	for p in c.parts:
		if int(p[1]) != 0:
			bits.append("%s %+d" % [p[0], p[1]])
	var target := "DC %d" % c.dc
	if c.has("opposed"):
		var o: Dictionary = c.opposed
		var obits := PackedStringArray(["d20 %d" % o.roll])
		for p in o.parts:
			if int(p[1]) != 0:
				obits.append("%s %+d" % [p[0], p[1]])
		target = "their %d (%s)" % [c.dc, ", ".join(obits)]
	var verdict := "[color=#2e6b3a]SUCCESS[/color]" if c.success else "[color=#a3261b]FAIL[/color]"
	if c.crit and c.success:  # both sides can roll a 20 (or a 1) in a contest
		verdict = "[color=#2e6b3a][b]CRITICAL![/b][/color]"
	elif c.fumble and not c.success:
		verdict = "[color=#a3261b][b]FUMBLE![/b][/color]"
	lines.append("%s = [b]%d[/b] vs %s  %s" % [", ".join(bits), c.total, target, verdict])
	return "\n".join(lines)
