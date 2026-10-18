extends Node2D
## The battle screen, turn by turn in the manner of Octopath Traveler. The ships fight on a BattleStage, an
## HD-2D diorama; this script runs the turns and the windows over it. The turn order runs across the top (this
## round, then the next, already rolled); each ship has a card with her hull, sails, crew and morale, her shields,
## and the weak points found so far. When one of your officers is up, pick an action and how many boost points to
## spend; the enemy's officers take their own turns in between. Allied ships, the boarding melee, and fire and leaks
## take turns in the order too. Keys: 1-9 pick an action, Q and E set the boost, R repeats this officer's last order,
## A carries on for the rest of the round (everyone repeats their last order).
## The UI is built in code (like the top bar) because it's rebuilt every turn anyway.

signal finished(result: Dictionary)

const ICONS := "res://assets/icons/hud/"
const SIDE_COL := [Color("#6fa8ff"), Color("#ff7a5c")]
const AI_PAUSE := 0.7     # seconds an enemy officer "thinks" before acting
const LINE_PAUSE := 0.3   # between log lines

var battle := DiceCombat.new()
var enemy_data: Dictionary
var stage: BattleStage
var busy := false
var boost := 0
var _cards: Array = []    # per side, the card's contents
var _order: HBoxContainer
var _info: Label
var _officer: HBoxContainer
var _boost_row: HBoxContainer
var _actions: GridContainer
var _log_box: RichTextLabel
var _dice: Label
var _choices: Array = []  # action ids in button order, for the number keys
var _carry_on := 0        # the round in which your officers repeat their orders without asking

@onready var dialog = $ChoiceDialog
@onready var hud: CanvasLayer = $HUD


func start(player_data: Dictionary, enemy: Dictionary, mode: String, _wind_dir: float, wind_strength: float) -> void:
	enemy_data = enemy
	battle.rng.randomize()
	var foe := enemy.duplicate(true)
	foe.party = DiceCombat.npc_party(enemy, battle.rng)
	battle.setup(DiceCombat.make_side(player_data), DiceCombat.make_side(foe), mode, wind_strength)
	var flags := [player_data.get("flag", "white"), Data.table("factions")[enemy.faction].flag]
	stage = BattleStage.new()
	add_child(stage)
	stage.setup(battle, flags, [player_data.get("look", {}), enemy.get("look", {})], wind_strength)
	_build_ui()
	var music := AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/Blackmoor Tides Loop.ogg")
	music.finished.connect(music.play)  # loop it; freed with the battle screen, so it stops when the battle ends
	add_child(music)
	music.play()
	_log("[i]The %s %s. Find her weak points, break her, and make her strike.[/i]" % [enemy.label, enemy.name])
	if not battle.sides[1].known.is_empty():
		_log("What you know of her: %s." % ", ".join(battle.sides[1].known.map(func(w): return DiceCombat.weak_name(w).to_lower())))
	for c in battle.conditions:
		_log("[b]%s.[/b] %s" % [c.name, c.text])
	var temper: String = battle.sides[1].get("temper", "")
	if temper != "":
		_log("Her captain, %s, is %s: %s." % [enemy.captain.name, DiceCombat.cfg().temperaments[temper].name, DiceCombat.cfg().temperaments[temper].text])
	_advance()


func _process(_delta: float) -> void:
	if stage:
		stage.sync(battle)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or busy or dialog.visible:
		return
	var k: int = event.keycode - KEY_1
	if k >= 0 and k < mini(9, _choices.size()):
		_choose(_choices[k])
	elif event.keycode == KEY_Q:
		_set_boost(boost - 1)
	elif event.keycode == KEY_E:
		_set_boost(boost + 1)
	elif event.keycode == KEY_R:
		_repeat()
	elif event.keycode == KEY_A:
		_carry_on_round()


# ---- the flow of turns --------------------------------------------------------

## Plays enemy turns (and round ends) until one of your officers is up, or the fight is over.
func _advance() -> void:
	busy = true
	while true:
		battle.entries = []
		var t := battle.turn()
		await _play_entries()
		if t.is_empty():
			_end()
			return
		boost = 0
		_show_turn(t)
		if t.side == 0 and _carry_on == battle.round_no:
			await get_tree().create_timer(LINE_PAUSE).timeout
			battle.entries = []
			battle.act(_repeat_pick(t.post))
			await _play_entries()
			if battle.result != "":
				_end()
				return
			continue
		if t.side == 0:
			break
		await get_tree().create_timer(AI_PAUSE).timeout
		battle.entries = []
		battle.act_ai()
		await _play_entries()
		if battle.result != "":
			_end()
			return
	busy = false


func _choose(id: String) -> void:
	if busy or battle.result != "":
		return
	busy = true
	if id == "strike" and await dialog.ask("Strike your colours?", "Surrender to the %s. They'll strip your hold and take half your gold." % enemy_data.name,
			[{"text": "Strike"}, {"text": "Fight on"}]) != 0:
		busy = false
		return
	battle.entries = []
	battle.act(id, 0 if id in ["", "strike"] else boost)
	await _play_entries()
	if battle.result != "":
		_end()
		return
	_advance()


## This officer's last order if it's still possible, else what a sensible officer would do.
func _repeat_pick(post: String) -> String:
	var last: String = battle.orders[0].get(post, "")
	if last != "" and last != "strike" and battle.available(0, post).has(last):
		return last
	return battle.ai_orders(0).get(post, "")


func _repeat() -> void:
	if not busy and not battle.queue.is_empty() and battle.queue[0].side == 0:
		_choose(_repeat_pick(battle.queue[0].post))


func _carry_on_round() -> void:
	if busy or battle.queue.is_empty() or battle.queue[0].side != 0:
		return
	_carry_on = battle.round_no
	_choose(_repeat_pick(battle.queue[0].post))


func _set_boost(k: int) -> void:
	if busy or battle.queue.is_empty() or battle.queue[0].side != 0:
		return
	var m: Dictionary = battle.sides[0].party[battle.queue[0].post]
	boost = clampi(k, 0, mini(int(DiceCombat.cfg().boost.max_spend), m.bp))
	_show_turn(battle.queue[0])


func _play_entries() -> void:
	var list := battle.entries.duplicate()
	battle.entries = []
	for e in list:
		_show_entry(e)
		await get_tree().create_timer(LINE_PAUSE).timeout
	_refresh()


# ---- building the screen --------------------------------------------------------

func _build_ui() -> void:
	var top := PanelContainer.new()  # the turn order
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	hud.add_child(top)
	_order = HBoxContainer.new()
	_order.add_theme_constant_override("separation", 5)
	top.add_child(_order)

	for i in 2:  # the ships' cards: yours on the left, hers on the right
		var card := PanelContainer.new()
		card.anchor_left = float(i)
		card.anchor_right = float(i)
		card.offset_left = 10.0 if i == 0 else -530.0
		card.offset_right = card.offset_left + 520.0
		card.offset_top = 92
		hud.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		_cards.append(box)

	_info = Label.new()  # the range and the gauge, between the cards
	_info.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_info.offset_top = 100
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.theme_type_variation = &"Header"
	_info.mouse_filter = Control.MOUSE_FILTER_PASS  # hover for what the conditions do
	_info.add_theme_constant_override("outline_size", 8)
	_info.add_theme_color_override("font_outline_color", Style.c("parchment_dark"))
	hud.add_child(_info)

	var bottom := PanelContainer.new()  # the officer whose turn it is, their orders, and the log
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 10
	bottom.offset_right = -10
	bottom.offset_top = -300
	bottom.offset_bottom = -10
	hud.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bottom.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	row.add_child(left)
	_officer = HBoxContainer.new()
	_officer.add_theme_constant_override("separation", 10)
	left.add_child(_officer)
	_boost_row = HBoxContainer.new()
	left.add_child(_boost_row)
	_dice = UIKit.label(left, "d20", "The last die rolled.")
	_dice.theme_type_variation = &"Title"
	_dice.add_theme_font_size_override("font_size", 54)
	_dice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mid := ScrollContainer.new()
	mid.custom_minimum_size = Vector2(660, 0)
	mid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(mid)
	_actions = GridContainer.new()
	_actions.columns = 2
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_actions)
	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = true
	_log_box.scroll_following = true
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_color_override("default_color", Style.c("ink"))
	var bold := FontVariation.new()
	bold.base_font = Style.font("body")
	bold.variation_embolden = 0.7
	_log_box.add_theme_font_override("normal_font", Style.font("body"))
	_log_box.add_theme_font_override("italics_font", Style.font("italic"))
	_log_box.add_theme_font_override("bold_font", bold)
	row.add_child(_log_box)
	_refresh()


func _refresh() -> void:
	_build_order()
	for i in 2:
		_build_card(i)
	var track := PackedStringArray()
	var bands: Array = DiceCombat.cfg().bands
	for b in bands.size():
		track.append("[ %s ]" % bands[b].to_upper() if b == battle.band else bands[b])
	_info.text = "  —  ".join(track) + "\n%s the weather gauge" % ("You hold" if battle.gauge == 0 else "They hold")
	if not battle.conditions.is_empty():
		_info.text += "\n" + "  ·  ".join(battle.conditions.map(func(c): return c.name))
	_info.tooltip_text = "\n\n".join(battle.conditions.map(func(c): return "%s: %s" % [c.name, c.text]))


func _build_order() -> void:
	UIKit.clear(_order)
	var r := UIKit.label(_order, "Round %d " % maxi(battle.round_no, 1), "Every officer on both ships acts once a round, fastest first: experience, the faster ship and the weather gauge, and a die.", Style.c("header"))
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in battle.queue.size():
		_chip(battle.queue[k], 52 if k == 0 else 40)
	var n := UIKit.label(_order, "   Next round:", "Next round's order is already rolled.", Style.c("dim"))
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for q in battle.next_queue:
		_chip(q, 30)


func _chip(q: Dictionary, px: int) -> void:
	if q.post.begins_with("@"):
		_special_chip(q, px)
		return
	var m: Dictionary = battle.sides[q.side].party[q.post]
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SIDE_COL[q.side]
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(5 if px >= 52 else (4 if px >= 40 else 3))
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tip := "%s %s: %s" % ["Your" if q.side == 0 else "Their", _post_name(q.post).to_lower(), m.name]
	if battle.is_broken(q.side):
		tip += "\nBroken: loses the turn."
		box.modulate.a = 0.35
	var c := _char_of(m)
	if c.is_empty():
		var l := UIKit.label(box, m.name.get_slice(" ", 0).left(2), tip, Style.c("wax_text"))
		l.custom_minimum_size = Vector2(px, px)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		var p := Portrait.make(c, "captain" if q.post == "captain" else "officer", px)
		p.tooltip_text = tip
		box.add_child(p)
	_order.add_child(box)


## Allies, the melee, and fire and leaks: shown in the order only when they'll happen.
func _special_chip(q: Dictionary, px: int) -> void:
	if not battle.special_applies(q):
		return
	var text := ""
	var tip := ""
	var col: Color
	if q.post.begins_with("@ally"):
		var a: Dictionary = battle.sides[0].allies[int(q.post.trim_prefix("@ally"))]
		text = "Ally"
		tip = "Your ally the %s fires a broadside." % a.name
		col = SIDE_COL[0].lightened(0.25)
	elif q.post == "@fort":
		text = "Fort"
		tip = "The fort at %s fires on %s." % [battle.fort().port_name, "you" if battle.fort().side == 0 else "her"]
		col = SIDE_COL[1 - int(battle.fort().side)].darkened(0.2)
	elif q.post == "@melee":
		text = "Melee"
		tip = "The boarders fight hand to hand: one roll, both sides take losses."
		col = Style.c("ink")
	else:
		text = "Fire" if battle.sides[q.side].fire > 0 else "Leaks"
		tip = "%s takes damage from fire and leaks." % ("Your ship" if q.side == 0 else "Their ship")
		col = Color("#c0661c")
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(2)
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(box, text, tip, Style.c("wax_text"))
	l.custom_minimum_size = Vector2(px + 8, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14 if px < 40 else 16)
	_order.add_child(box)


func _build_card(i: int) -> void:
	var box: VBoxContainer = _cards[i]
	UIKit.clear(box)
	var s: Dictionary = battle.sides[i]
	var title := UIKit.label(box, "%s  (%s)%s" % [s.name, Data.table("ships")[s.type].name, "  — struck" if s.struck else ""])
	title.theme_type_variation = &"Header"
	title.add_theme_color_override("font_color", SIDE_COL[i])
	_bar(box, "hull", "Hull", s.hull, s.stats.hull, Color("#6b3d1a"), "%d / %d" % [s.hull, s.stats.hull])
	_bar(box, "sails", "Sails", s.sails, s.stats.sails, Color("#9a8650"), "%d / %d, masts %d" % [s.sails, s.stats.sails, s.masts])
	_bar(box, "crew", "Crew", s.crew, s.crew_start, SIDE_COL[0].lerp(Style.c("ink"), 0.3),
		("%d, guns %d" if i == 0 else "about %d, guns %d") % [s.crew if i == 0 else int(s.crew / 5.0) * 5, s.guns_working])
	_bar(box, "morale", "Morale", s.morale, 100.0, Style.c("good") if s.morale >= DiceCombat.cfg().morale_check_below else Style.c("bad"), "%d" % s.morale)

	var row := UIKit.row(box)
	var tip := "Hit a weak point to strip shields (one, plus one for every boost point spent). At none she is Broken: she loses her turns this round and next, her rolls are at %d, and she takes half again the damage." % DiceCombat.cfg().breaks.reeling
	UIKit.label(row, "Shields  ", tip)
	if battle.is_broken(i):
		UIKit.label(row, "BROKEN — reeling until round %d is done" % s.broken, tip, Style.c("bad"))
	else:
		for k in s.shields_max:
			_pip(row, k < s.shields, SIDE_COL[i], 16, tip)

	var weak := HFlowContainer.new()  # wraps when she has many weak points
	box.add_child(weak)
	UIKit.label(weak, "Weak points:  ", "What strips her shields." if i == 1 else "What strips your shields. Ones marked * the enemy has found.")
	var tips: Dictionary = DiceCombat.cfg().breaks.tips
	for w in s.weak:
		var found: bool = w in s.known
		if i == 1 and not found:
			UIKit.label(weak, "[ ? ]  ", "A weak point you haven't found. Your navigator can study her through the glass, or you may find it by hitting it.", Style.c("dim"))
		else:
			UIKit.label(weak, "[ %s%s ]  " % [DiceCombat.weak_name(w), "*" if i == 0 and found else ""], "Struck by: %s." % tips[w], Style.c("header"))

	var trouble := PackedStringArray()
	if s.leak > 0: trouble.append("LEAKING")
	if s.fire > 0: trouble.append("ON FIRE")
	if s.rudder > 0: trouble.append("rudder damaged")
	if s.armed: trouble.append("boarders armed")
	if not trouble.is_empty():
		UIKit.label(box, ", ".join(trouble), "", Style.c("bad"))


func _bar(parent: Node, icon: String, name: String, v: float, most: float, col: Color, text: String) -> void:
	var row := UIKit.row(parent)
	UIKit.icon(row, ICONS + icon + ".png", 20)
	UIKit.label(row, name).custom_minimum_size.x = 62
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = maxf(most, 1.0)
	pb.value = clampf(v, 0.0, pb.max_value)
	pb.custom_minimum_size = Vector2(240, 14)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Style.c("ink"), 0.12)
	bg.border_color = Color(Style.c("ink"), 0.6)
	bg.set_border_width_all(1)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bg)
	row.add_child(pb)
	UIKit.label(row, "  " + text)


## A pip: shields (diamonds) and boost points (squares).
func _pip(parent: Node, full: bool, col: Color, px: int, tip: String, diamond := true) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px + 8, px + 8)
	holder.tooltip_text = tip
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col if full else Color(col, 0.1)
	sb.border_color = col
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(px, px)
	p.position = Vector2(4, 4)
	p.pivot_offset = Vector2(px, px) / 2.0
	p.rotation = PI / 4.0 if diamond else 0.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(p)
	parent.add_child(holder)


func _show_turn(t: Dictionary) -> void:
	UIKit.clear(_officer)
	UIKit.clear(_boost_row)
	UIKit.clear(_actions)
	_choices = []
	var s: Dictionary = battle.sides[t.side]
	var m: Dictionary = s.party[t.post]
	var c := _char_of(m)
	if not c.is_empty():
		_officer.add_child(Portrait.make(c, "captain" if t.post == "captain" else "officer", 80))
	var who := VBoxContainer.new()
	_officer.add_child(who)
	UIKit.label(who, "%s %s" % ["Your" if t.side == 0 else "Their", _post_name(t.post).to_lower()], "", SIDE_COL[t.side]).theme_type_variation = &"Header"
	UIKit.label(who, m.name + (" (wounded)" if m.get("wounded", false) else ""))
	var skill: String = DiceCombat.cfg().post_skills[t.post]
	UIKit.label(who, "%s %d (%+d)" % [People.SKILL_NAMES.get(skill, skill), DiceCombat.value(m, skill), Dice.mod(DiceCombat.value(m, skill))], "", Style.c("dim"))

	var b: Dictionary = DiceCombat.cfg().boost
	var tip := "Boost points: one banked each round (not the round after you boost), up to %d. Spend up to %d on an action: +%d to the roll per point, an extra die of damage for a broadside, and an extra shield stripped from a weak point. Q and E to change." % [b.max_points, b.max_spend, b.per_point]
	UIKit.label(_boost_row, "Boost ", tip)
	for k in int(b.max_points):
		_pip(_boost_row, k < m.bp, Style.c("flash").darkened(0.25), 12, tip, false)
	if t.side == 1:
		UIKit.label(_actions, "Their %s is giving orders..." % _post_name(t.post).to_lower(), "", Style.c("dim"))
		return
	UIKit.label(_boost_row, "  spend:")
	for k in int(b.max_spend) + 1:
		var bb := UIKit.button(_boost_row, " %d " % k, _set_boost.bind(k), tip)
		bb.toggle_mode = true
		bb.button_pressed = k == boost
		bb.disabled = k > m.bp

	var can := battle.available(0, t.post)
	var n := 0
	for id in can:
		n += 1
		var a: Dictionary = can[id]
		var pv := battle.preview(0, t.post, id, 0 if id == "strike" else boost)
		var tag: String = a.get("ammo", a.get("hits", ""))
		var weak: bool = tag != "" and tag in battle.sides[1].known and not battle.is_broken(1)
		var text := "%d   %s   %d%%%s" % [n, a.name, int(round(pv.chance * 100)), "   WEAK POINT!" if weak else ""]
		var help: String = a.description + "\n\n" + _explain(pv)
		if weak:
			help += "\n\nHits her weak point (%s): strips %d shield%s." % [DiceCombat.weak_name(tag).to_lower(), 1 + boost, "" if boost == 0 else "s"]
		var btn := UIKit.button(_actions, text, _choose.bind(id), help)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(320, 0)
		if weak:
			btn.add_theme_color_override("font_color", Style.c("flash"))
		_choices.append(id)
	var wait := UIKit.button(_actions, "%d   Wait" % (n + 1), _choose.bind(""), "Do nothing this turn. Unspent boost points stay banked.")
	wait.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_choices.append("")
	var again := _repeat_pick(t.post)
	if again != "":
		var r := UIKit.button(_actions, "R   Same again: %s" % can[again].name, _repeat, "Repeat this officer's last order (or the sensible one), without boost.")
		r.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var all := UIKit.button(_actions, "A   Carry on this round", _carry_on_round, "Every officer of yours repeats their last order for the rest of this round. You take the helm again next round.")
	all.alignment = HORIZONTAL_ALIGNMENT_LEFT


## The roll an action needs, for its tooltip.
func _explain(pv: Dictionary) -> String:
	if pv.parts.is_empty() and pv.get("dc", 0) == 0 and not pv.has("opp"):
		return "No roll needed."
	var out := "d20" + _parts_text(pv.parts)
	if pv.has("opp"):
		out += "\nagainst their d20" + _parts_text(pv.opp)
	else:
		out += "\nagainst DC %d" % pv.dc
	return out + "\nChance: %d%%" % int(round(pv.chance * 100))


static func _parts_text(parts: Array) -> String:
	var bits := PackedStringArray()
	for p in parts:
		bits.append("%s %+d" % [p[0], p[1]])
	return "" if bits.is_empty() else ": " + ", ".join(bits)


func _char_of(m: Dictionary) -> Dictionary:
	if m.get("id", "") != "" and People.chars.has(m.id):
		return People.person(m.id)
	return m.get("char", {})


static func _post_name(post: String) -> String:
	return "Captain" if post == "captain" else Data.rules.officer_roles[post].name


# ---- the log ------------------------------------------------------------------

func _show_entry(e: Dictionary) -> void:
	var who := "" if e.side < 0 or e.post == "" else ("[color=#6fa8ff]You[/color] - " if e.side == 0 else "[color=#ff7a5c]Them[/color] - ")
	var text: String = who + e.text
	if e.text.begins_with("BREAK"):
		text = "[b][color=#ff5a3c]%s[/color][/b]" % e.text
		_shake()
	elif e.text.begins_with("Round "):
		text = "[b]%s[/b]" % e.text
	elif e.text.begins_with("A weak point"):
		text = "[color=#ff7a5c]%s[/color]" % e.text
	if not e.check.is_empty():
		text += "\n      " + Dice.describe(e.check)
		_dice.text = str(e.check.roll)
		_dice.add_theme_color_override("font_color", Style.c("good") if e.check.success else Style.c("bad"))
	_log(text)
	if e.post == "master_gunner" and e.side >= 0 and not e.check.is_empty():
		stage.broadside(e.side, e.check.success)
	elif e.text.begins_with("Your ally the "):
		stage.broadside(0, not e.text.contains("misses"), _ally_named(e.text))
	elif e.text.begins_with("The fort at "):
		stage.fort_fire(other_side(e.side), e.text.contains(" hits "))


static func other_side(i: int) -> int:
	return 1 - i


func _log(text: String) -> void:
	_log_box.append_text(text + "\n")


func _shake() -> void:
	stage.shake(0.6)


func _ally_named(text: String) -> String:
	for a in battle.sides[0].get("allies", []):
		if text.begins_with("Your ally the %s " % a.name):
			return a.name
	return ""


# ---- the end -----------------------------------------------------------------

func _end() -> void:
	busy = true
	UIKit.clear(_actions)
	var titles := {"enemy_struck": "She strikes her colours!", "player_struck": "You strike your colours",
		"enemy_sunk": "She goes down", "player_sunk": "Your ship is lost", "separated": "The ships part"}
	var texts := {
		"enemy_struck": "The %s is yours. Time to decide what to do with her." % enemy_data.name,
		"player_struck": "The fight is lost. The enemy boards to take what they want.",
		"enemy_sunk": "The %s slips beneath the waves, cargo and all." % enemy_data.name,
		"player_sunk": "The sea takes your ship.",
		"separated": "The distance grows until the %s is just a sail on the horizon." % enemy_data.name,
	}
	var me: Dictionary = battle.sides[0]
	if battle.result.ends_with("sunk"):
		await stage.sink(1 if battle.result == "enemy_sunk" else 0).finished
	var text: String = texts[battle.result] + "\n\nRounds fought: %d.  Your casualties: %d.  Hull %d, sails %d." % [battle.round_no, me.casualties, me.hull, me.sails]
	if me.captain_wounded:
		text += "\nYour captain was wounded."
	await dialog.ask(titles[battle.result], text, [{"text": "Continue"}])
	finished.emit({"outcome": battle.result, "player": me, "enemy": battle.sides[1], "enemy_data": enemy_data})
