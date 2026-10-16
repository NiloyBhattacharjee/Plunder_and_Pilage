class_name Portraits
## Layered character portraits built from data/portraits.json. Each character keeps a portrait seed, so the
## same face rebuilds after loading. Faces follow the story: wounds add an eyepatch, scar or hook; age greys
## the hair and adds wrinkles; role and background pick the clothing (a navy coat, a pirate's, a governor's wig).
## A character's chosen looks (c.portrait.pick: {layer: part id, or "" for none}, c.portrait.skin, .hair) override
## the dice, but never the story: an eyepatch earned in battle stays.

const EDITABLE := ["background", "head", "eyes", "nose", "mouth", "hair", "facial_hair", "body", "hat", "accessory", "tattoo"]


## Tags that steer clothing and hats for this character in this role ("crew", "officer", "captain", "official"...).
static func tags_for(c: Dictionary, role: String) -> Array:
	var tags := [role]
	match c.get("background", ""):
		"ex_navy": tags.append("navy")
		"merchant_son": tags.append("merchant")
		"indentured", "disgraced_privateer": tags.append("pirate")
	if "former_navy" in c.traits:
		tags.append("navy")
	if "bloodthirsty" in c.traits or "greedy" in c.traits:
		tags.append("pirate")
	return tags


## The layers to draw, bottom to top: [{texture, color}].
static func layers(c: Dictionary, tags: Array) -> Array:
	var d: Dictionary = Data.table("portraits")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("portrait", {}).get("seed", hash(c.name)))
	var nat: String = c.get("nationality", "english")
	var look: Dictionary = c.get("portrait", {})
	var chosen: Dictionary = look.get("pick", {})
	var skin := Color(_pick(rng, d.skin_tones.get(nat, d.skin_tones.default)))
	var hair := Color(_pick(rng, d.hair_colors.get(nat, d.hair_colors.default)))
	if look.has("skin"):
		skin = Color(look.skin)
	if look.has("hair"):
		hair = Color(look.hair)
	var age: int = c.get("age", 30)
	hair = hair.lerp(Color(d.grey), clampf(float(age - d.grey_from_age) / (d.grey_full_age - d.grey_from_age), 0.0, 1.0))
	var out := []
	for layer in d.layers:
		# Always draw both rolls, so switching a story layer on never reshuffles the rest of the face.
		var roll_none := rng.randf()
		var roll_pick := rng.randi()
		var story: String = d.story_layers.get(layer, "")
		if story == "age":
			if age < d.wrinkles_from_age:
				continue
		elif story != "":
			if not story in c.traits:
				continue
		elif chosen.has(layer):
			if chosen[layer] == "":
				continue
		elif roll_none < d.none_chance.get(layer, 0.0):
			continue
		var parts: Array = d.parts[layer]
		var mine := parts.filter(func(p): return p.id == chosen.get(layer, ""))
		if story == "" and not mine.is_empty():
			parts = mine
		# prefer the parts that fit the most tags: a navy captain gets the navy coat, not just any captain's coat
		var best := 0
		for p in parts:
			best = maxi(best, p.tags.filter(func(t): return t in tags).size())
		var pool := parts.filter(func(p): return best > 0 and p.tags.filter(func(t): return t in tags).size() == best)
		if pool.is_empty():
			pool = parts.filter(func(p): return "any" in p.tags)
		if pool.is_empty():
			pool = parts
		var part: Dictionary = pool[roll_pick % pool.size()]
		var color := Color.WHITE
		match d.modulate.get(layer, ""):
			"skin": color = skin
			"hair": color = hair
		out.append({"texture": load(part.path), "color": color, "id": part.id, "layer": layer})
	return out


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]
