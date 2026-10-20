# Writing events

Events live in `data/events/*.json`. Every file there is loaded, so add new batches as new files (`sea_2.json`, `crew_more.json`...).
The game checks every event at startup and the test suite fails on any mistake (unknown condition, outcome, trait, good, role or chained event),
so run the tests after adding a batch.

```json
"drunk_on_watch": {
  "title": "Asleep on watch",
  "text": "{drunk} is found snoring at the masthead, an empty bottle in his lap.",
  "where": "sea",
  "weight": 10,
  "weight_mods": [["cargo.rum >= 20", 2.0]],
  "conditions": ["crew >= 5"],
  "roles": {"drunk": {"from": "crew", "where": ["trait.drunkard"]}},
  "choices": [
    {"text": "Flog him", "outcomes": ["opinion {drunk} -10", "fear +1"], "result": "Twelve lashes at the grating."},
    {"text": "Talk sense into him", "check": {"who": "captain", "skill": "charisma", "dc": 12},
     "outcomes": ["untrait {drunk} drunkard"], "result": "He swears off the bottle.",
     "fail_outcomes": ["opinion crew -2"], "fail_result": "He laughs it off."}
  ]
}
```

Characters have no gender in the data (crew names include Grace, Isobel, Catalina, Abena...), so never write he/she for a role:
use the role's name or "they". Historical figures and strangers described in the text ("an old buccaneer") are fine.

## Fields

| Field | Meaning |
|---|---|
| `title`, `text` | Shown in the dialog. `{captain}`, `{ship}`, `{port}` and every role are filled in. `{role_adj}` gives a nation's adjective. |
| `where` | `sea` (daily roll at sea, the default), `port` (on arrival) or `any`. |
| `find` | Makes it a thing found at sea instead of a daily roll: it waits on the map as a marker of this kind (`cask`, `boat`, `wreck`, `wreckage`, `whale`, `bottle`, `castaway`, `fish`, `turtle`, `satchel`; see `rules.json` `finds`) and happens when you sail up to it. `find_near`: `sea` (deep water, the default) or `reef`. |
| `weight` | Relative chance against other valid events (default 10). `weight_mods`: `[condition, multiplier]` pairs. |
| `conditions` | All must hold. |
| `roles` | Variables bound when the event fires (see below). If a role can't be filled, the event can't fire. |
| `once` | Fires at most once per game. Otherwise `cooldown` days (default in `rules.json` `events`). |
| `priority` | Fires as soon as its conditions hold (historical moments). Use with `once` and a date window. |
| `chain_only` | Only fires when another event queues it. |
| `story`, `act` | Part of a story (see Stories below). |
| `choices` | 1 to 4. Each has `text`, optional `conditions` (unmet ones show greyed out with the reason), optional `check`, `outcomes`, `result`, and for checks `fail_outcomes` and `fail_result`. `hidden: true` hides the effect preview in the tooltip. |
| `voice` | On a choice: how your people see it, `{"cruel": 2, "decent": -1, "greedy": 1, "bold": 1}` (negative: mercy, a dirty trick, money out, backing off). Officers and the hands you know speak for or against choices from their traits, and remember whether you listened (data/voices.json). Left out, it's read from the outcomes (`kill`, `fear`, `honour`, `gold`, `loot`, `fight`); `{}` keeps them quiet. Not the people the event is about. |
| `check` | `{"who": "captain" or "post.surgeon" or "{role}", "skill": skill or stat, "dc": n, "bonus": [[condition, label, modifier]]}`. A d20 roll, shown in full; whoever rolls learns from it. |

## Roles

`{"from": source, "where": [conditions on the candidate]}`. Sources: `crew`, `officer`, `captain`, `new` (a stranger who can be hired with `hire {role}`; `"pool": "official"` for officials; `"nation": "{role}"` to draw them from that nation; `"name"` and `"traits"` for historical figures),
`port`, `here` (the port you're in), `nation`, `enemy` (a nation at war with your home or your commission), `ringleader` (the leader of the unrest, if there is one), `official` (an official of the port you're in), `creditor` (someone you owe a favour), `enemy_official` (an official or council captain who hates you), `council` (a Nassau council captain), `ally` and `rival` (a person you're bound to), `captain_npc` (a named captain from the roster), `base` (one of your bases: candidate keys `loyalty`, `visibility`, `garrison`, `built.BUILDING`, `managed`, `manager_opinion`, `town` (a town you hold), `taxes` (`light`, `fair`, `heavy`)), `good`, `number` (`"range": [min, max]`).

Candidate conditions: characters `trait.X`, `known_trait.X`, `opinion` (of the captain), `officer`, `post`, `nationality`, `age`, `hidden`, any stat or skill;
ports `faction`, `fence`, `here`, `contraband`, `shipyard`; nations `at_war.X`, `mine`, `standing` (yours with them); goods `price`, `held`. Any other key is read from the player's situation.

## Conditions

`key`, `not key`, or `key op value` with `== != < > <= >=`. Use `{role}` to compare with a bound value.

Numbers: `gold`, `crew` (headcount), `hull`, `sails` (percent), `notoriety`, `honour`, `fear`, `loyalty` (the crew's average opinion of the captain),
`food`, `water` (days left), `wages_owed`, `owes` (people you owe favours), `allies`, `rivals`, `bases`, `towns` (towns you hold), `bounty` (the price on your head, all nations), `secrets`, `power.GROUP` (influence here, percent), `morale`, `unrest` (0-5: grumbling, round robin, weapons missing, black spot, mutiny), `sick`, `crew_share` (percent), `prizes`, `hostages`, `contracts`, `year`, `month`, `guns`, `stolen`, `cargo.GOOD`, `relation.FACTION`, `captain.STAT_OR_SKILL`.

Faction words: `relation.X`, `war.X.Y`, `port_is.X` and the candidate key `at_war.X` also accept `port` (the port you're in), `home` and `marque`.

The town you're in (scripts/port_life.gd): `town.wealth`, `town.prosperity`, `town.hunger`, `town.order`, `town.piety` (0-100), and yes/no `town.war`, `town.lawless`, `town.fleet`. What's going on there: `life.festival`, `life.press_gang`, `life.bread_riot`... (the happenings in data/port_life.json). Candidate key `in_town`: a character drinking in this port's tavern.
What it remembers of you: `regard` (-100 to 100), and yes/no `deed.ID` (a deed it still remembers: the deeds in data/port_life.json `_memory`).

Yes/no: `own_town` (you hold the town you're in), `sacked` (you sacked the town you're in), `at_base` (anchored at one of your coves), `neutral` (no alliances or rivalries), `council_member`, `council_leader`, `unrest_known`, `shares` (no prey, no pay), `port_is.FACTION`, `at_sea`, `in_port`, `storm`, `pirate`, `privateer`, `honest`, `wanted`, `pardoned`, `pardon_open.FACTION`, `war.A.B`, `flag.NAME`,
`contract.TEMPLATE`, `captain_trait.TRAIT`, `has_officer.POST`, `port_fence`, `true`.

Stories: `story.ID` (the act an open story is at, 0 if it isn't running).

Text: `date` (`"date >= 1715-07-31"`), `ship` (type), `port`, `port_faction`, `marque`, `home`.

## Outcomes

| Outcome | Effect |
|---|---|
| `gold +100`, `gold -10%` | Money |
| `crew +3`, `crew -2` | Recruits from the local mix, or random hands lost |
| `kill {r}`, `leave {r}`, `wound {r}`, `hire {r}` | One person (`kill captain` really kills the captain: someone else takes over) |
| `leave {r} marooned`, `kill {r} hanged` | How they go: `dismissed` (the default for leave), `marooned`, `hanged`, `handed_over`, `deserted`, `blessed`, `died`. Sets what it costs: friends aboard resent it, their home town remembers, and a dismissed one may come back as a rival captain who knows your ship (`_parting` in data/wants.json). A death passes their cause to a friend. |
| `opinion {r} +5`, `opinion crew -3` | Their opinion of the captain |
| `relation spain -5` | Standing. Also `port` (this port's nation), `home`, `marque`, or a `{role}` holding a nation |
| `honour +2`, `fear +1`, `notoriety +3` | Reputation |
| `cargo rum +20`, `cargo {good} -all`, `loot silver 10`, `food +30`, `water -10` | Hold (`loot` marks it stolen) |
| `hull -15`, `sails -10`, `wages +50`, `paywages` | Ship and pay (`paywages` pays what you can of the back wages) |
| `skill {r} gunnery +1`, `trait {r} brave`, `untrait {r} drunkard`, `reveal {r}` | People change |
| `flag NAME [days]`, `unflag NAME` | Remember something for later events |
| `morale +10 30` | A morale modifier for 30 days, named after the event |
| `patrols spain 30` | You know where that navy patrols for 30 days: its ships won't trouble you |
| `calm 3`, `expose`, `share +0.1` | Talk 3 plotters round; learn who leads the unrest; change the crew's share |
| `confidence`, `mutiny`, `depose` | A vote of confidence (lose it and you're out); the mutiny breaks now; the captain steps down |
| `favour {r} +1`, `secret KIND [{r} or any] [fake]`, `scandal {r}` | Favours (negative: you owe them); a secret (letters, ledger, bribes, schedule) about someone; an official recalled in disgrace |
| `influence PORT GROUP +5`, `stir 4`, `council_vote TOPIC yes/no`, `join_council` | Shift a port's interest groups; someone pays your crew to plot; the Nassau council votes (with your voice) |
| `bond {r} +1`, `rivalry {r} 2`, `strain {r}`, `betray {r}`, `peace {r}` | Alliances and rivalries (scripts/bonds.gd): raise or lower an alliance, start or worsen a rivalry, strain a bond (two strains and it drops a level), an ally turns on you, a rivalry ends |
| `reveal_cove`, `base_gold {b} -15%`, `base_loyalty {b} -10`, `base_visibility {b} +10`, `base_garrison {b} +4`, `base_store {b} sugar +30`, `base_damage {b}`, `base_lost {b}` | Bases (scripts/bases.gd): learn of a hidden cove; change a base you own; destroy a building; lose the base |
| `bounty spain +500`, `bounty port -40%` | The price on your head with a nation (scripts/career.gd) |
| `intel {captain}` | Learn every weak point of a named captain's ship: shown in battle before the first shot |
| `abandon TEMPLATE` | Fails your active contract of that template (a double-cross, a bribe taken) |
| `event ID [delay] [window]` | Chain: queue another event, with the same roles, after `delay` days; it waits up to `window` days for its conditions |
| `ending STORY KEY` | Closes a story with one of its endings (data/stories.json) |
| `fight KIND [faction] [mode]` | A battle: `merchant`, `pirate`, `navy`, `hunter`; mode `defend` (default), `attack`, `ambush`, `flee` |
| `market PORT shortage` | Sets off a market shock from `economy.json` `shocks` (`shortage`, `glut`, `bad_harvest`, `hurricane`, `epidemic`, `warehouse_fire`, `garrison_reinforced`, `coin_shortage`, `piracy_wave`, `bankruptcy`) |
| `time 3` | Days pass |
| `want {r} done`, `want {r} ignored` | A person's want (data/wants.json) seen to (they're yours: opinion up, loyal) or let go (they remember) |
| `deed fed_hungry` | The town you're in remembers what you did: its regard for you moves (data/port_life.json `_memory` `deeds`) |

## Stories

A story is a pre-written chain with a start, a peak and an ending: `data/stories.json` gives its title, summary, act names,
endings (`{name, text}`, the text can use the story's roles), optional `boost` (`{event_id: multiplier}`: those events are likelier
while it runs) and `repeat` (it can be told again once it ends). Its events (most of them in `data/events/stories.json`) carry
`"story"` and `"act"`. Act 1 is the hook: it fires like any event, but only if the story hasn't been told and fewer than
`rules.json` `events.max_stories` are running. Later acts are `chain_only` and come through `event` outcomes, carrying the roles,
so each one must declare the roles it uses again. A choice that starts a battle can name what follows it: `"won": "event_id"` and
`"lost": "event_id"` (lost: anything but taking or sinking her, fleeing included). Every choice of a story event must go
somewhere: on to another of its events, into a fight with `won` and `lost`, or to `ending STORY KEY`; the validator checks it.
If a chain runs out before its next act can happen (the window passes, someone in it dies), the story goes cold. The ship's log
lists every story, the act it's at and what's happened so far.

## Structured effects (the market and the world)

Beside its string `outcomes`, a choice can carry `"effects": [...]` (and `"fail_effects"`): objects shaped
`{"type": ..., params}`, the shape the Johnson events use. `scripts/economy/effects.gd` handles them; a type it
doesn't know logs a warning and is skipped (the validator warns at startup too). Ports: an id, `"current"` (where the
player is), or a role of the event that names a port. Durations are `days`.

| Type | Params | What it does |
|---|---|---|
| `market_shock` | port, goods (ids or aliases, a list or `a/b`), price_multiplier, days | Stock falls (or rises) to move the price that much, and supply stays short for the days, then trade restores it |
| `port_damage` | port, severity 0-1 | Warehouses wrecked, production cut, fewer sailings for months |
| `open_market` | kind, price_bonus (%), days | A smugglers' market here: forbidden goods sell for the bonus, no customs |
| `port_closed_days` | port, days | The harbour won't let you in |
| `free_supplies` | port, days | Provisions and water cost nothing there |
| `repair_discount` | percent, days | Shipyard repairs cost less |
| `trade_profit_multiplier` | value, days | Everything you sell fetches that much more (or less) |
| `merchant_resistance_multiplier` | value, days | Merchants' morale in a fight, times this |
| `buy_provisions` | days, price_multiplier | Buy that many days of food for the crew at that price |
| `sell_items` | items, price_multiplier | Sell what you hold of those goods at that share of their worth |
| `launder_prize`, `prize_unsellable_here` | | Your prizes' cargo sells as lawful; no yard here will buy your prize |
| `unlock_fence`, `fence_trust` (amount), `fence_dependence` (amount) | | A fence here for you; trust raises (or lowers) what a fence pays; dependence lowers it |
| `rep_with_smugglers` | amount | Better contacts: less risk of seizure when you smuggle |
| `unlock_trade_with` | npc | Remembered, for content that trades with that captain |
| `treat_ships_from`, `faction_port_hostility` | port, days / amount | That port's nation's warships attack you on sight; your standing with it falls |
| `bombard_port`, `burn_ships_in_road` | severity / count | Damage the port (and your standing); destroy ships in the roads (their voyages are lost) |
| `war` | between [a, b], until YYYY-MM-DD | War, ending on the date |
| `world_state` | key, value, days | A world condition, and a flag events can test |
| `pirate_spawn_rate_multiplier` | value, days | More (or fewer) pirates at sea, and merchants lost to them |
| `letter_of_marque`, `revoke_letter_of_marque` | faction | Grant or cancel the player's commission |
| `gold`, `gold_percent`, `cargo_percent`, `provisions` | amount, percent, days | Money and supplies |
| `fleet_blocked`, `trade_slump`, `fair_access`, `port_laws`, `flows`, `stock`, `spread`, `sailings`, `route_risk` | | History's own (data/history.json): a blockade, a credit crash, the asiento, new laws in a port, and the raw market levers shocks use |

`start_land_raid` is known but isn't the market's business: it's logged and skipped.

