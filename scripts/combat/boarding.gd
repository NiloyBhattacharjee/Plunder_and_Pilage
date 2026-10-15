class_name Boarding
## Boarding as a few rounds of decisions. Each side's strength comes from fighters, their swordplay and morale;
## a side breaks when its morale or numbers collapse. Sides are plain dicts:
##   {crew, swordplay, captain_swordplay, morale, casualties, swivels}


static func cfg() -> Dictionary:
	return Data.rules.boarding


static func strength(side: Dictionary, mult: float) -> float:
	return side.crew * (0.5 + side.swordplay / 20.0) * (0.5 + maxf(side.morale, 0.0) / 100.0) * mult


## Swivel guns sweep the enemy deck as the ships come together. Returns lines for the report.
static func opening_volley(player: Dictionary, enemy: Dictionary, rng: RandomNumberGenerator) -> Array:
	var lines := []
	for pair in [[player, enemy, "Your swivel guns"], [enemy, player, "Their swivel guns"]]:
		var shooter: Dictionary = pair[0]
		if shooter.get("swivels", 0) > 0:
			var kills := minf(pair[1].crew, shooter.swivels * cfg().swivel_kills * rng.randf_range(0.6, 1.4))
			_lose(pair[1], kills)
			lines.append("%s cut down %d as the ships grind together." % [pair[2], kills])
	return lines


## The enemy's choice: press when stronger, otherwise hold.
static func enemy_choice(enemy: Dictionary, player: Dictionary) -> String:
	if enemy.morale > 40 and strength(enemy, 1.0) > strength(player, 1.0):
		return "push"
	return "hold"


## One round. Returns {lines, player_loss, enemy_loss, result: "" | "won" | "lost"}.
static func fight_round(player: Dictionary, enemy: Dictionary, choice: String, enemy_pick: String, rng: RandomNumberGenerator) -> Dictionary:
	var c := cfg()
	var pc: Dictionary = c.choices[choice]
	var ec: Dictionary = c.choices[enemy_pick]
	var lines := []
	if choice == "captain":
		var mine: float = player.captain_swordplay + rng.randf_range(0.0, 10.0)
		var theirs: float = enemy.captain_swordplay + rng.randf_range(0.0, 10.0)
		if mine >= theirs:
			enemy.morale -= c.duel_win_morale
			enemy.captain_down = true
			lines.append("Your captain fights through to theirs and cuts them down! Their crew wavers.")
		else:
			player.morale -= c.duel_lose_morale
			player.captain_wounded = true
			lines.append("Their captain gets the better of yours, who falls back wounded. Your crew falters.")
	var ps := strength(player, pc.deal)
	var es := strength(enemy, ec.deal)
	var enemy_loss := minf(enemy.crew, ps * c.casualty_rate * rng.randf_range(0.7, 1.3) * ec.take)
	var player_loss := minf(player.crew, es * c.casualty_rate * rng.randf_range(0.7, 1.3) * pc.take)
	_lose(enemy, enemy_loss)
	_lose(player, player_loss)
	player.morale += pc.morale
	enemy.morale += ec.morale
	lines.append("You lose %d men, they lose %d. Your morale %d, theirs %d." % [player_loss, enemy_loss, player.morale, enemy.morale])
	var result := ""
	if enemy.morale <= c.break_morale or enemy.crew < 3:
		result = "won"
	elif player.morale <= c.break_morale or player.crew < 3:
		result = "lost"
	return {"lines": lines, "player_loss": player_loss, "enemy_loss": enemy_loss, "result": result}


static func _lose(side: Dictionary, n: float) -> void:
	var before: float = side.crew
	side.crew -= n
	side.casualties = side.get("casualties", 0.0) + n
	side.morale -= n / maxf(before, 1.0) * 100.0 * 0.8
