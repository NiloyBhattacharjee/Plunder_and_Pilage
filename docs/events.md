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
| `weight` | Relative chance against other valid events (default 10). `weight_mods`: `[condition, multiplier]` pairs. |
| `conditions` | All must hold. |
| `roles` | Variables bound when the event fires (see below). If a role can't be filled, the event can't fire. |
| `once` | Fires at most once per game. Otherwise `cooldown` days (default in `rules.json` `events`). |
| `priority` | Fires as soon as its conditions hold (historical moments). Use with `once` and a date window. |
| `chain_only` | Only fires when another event queues it. |
| `choices` | 1 to 4. Each has `text`, optional `conditions` (unmet ones show greyed out with the reason), optional `check`, `outcomes`, `result`, and for checks `fail_outcomes` and `fail_result`. `hidden: true` hides the effect preview in the tooltip. |
| `check` | `{"who": "captain" or "post.surgeon" or "{role}", "skill": skill or stat, "dc": n, "bonus": [[condition, label, modifier]]}`. A d20 roll, shown in full; whoever rolls learns from it. |

## Roles

`{"from": source, "where": [conditions on the candidate]}`. Sources: `crew`, `officer`, `captain`, `new` (a stranger who can be hired with `hire {role}`; `"pool": "official"` for officials; `"nation": "{role}"` to draw them from that nation; `"name"` and `"traits"` for historical figures),
`port`, `here` (the port you're in), `nation`, `enemy` (a nation at war with your home or your commission), `ringleader` (the leader of the unrest, if there is one), `official` (an official of the port you're in), `creditor` (someone you owe a favour), `enemy_official` (an official or council captain who hates you), `council` (a Nassau council captain), `good`, `number` (`"range": [min, max]`).

Candidate conditions: characters `trait.X`, `known_trait.X`, `opinion` (of the captain), `officer`, `post`, `nationality`, `age`, `hidden`, any stat or skill;
ports `faction`, `fence`, `here`, `contraband`, `shipyard`; nations `at_war.X`, `mine`, `standing` (yours with them); goods `price`, `held`. Any other key is read from the player's situation.

## Conditions

`key`, `not key`, or `key op value` with `== != < > <= >=`. Use `{role}` to compare with a bound value.

Numbers: `gold`, `crew` (headcount), `hull`, `sails` (percent), `notoriety`, `honour`, `fear`, `loyalty` (the crew's average opinion of the captain),
`food`, `water` (days left), `wages_owed`, `owes` (people you owe favours), `secrets`, `power.GROUP` (influence here, percent), `morale`, `unrest` (0-5: grumbling, round robin, weapons missing, black spot, mutiny), `sick`, `crew_share` (percent), `prizes`, `hostages`, `contracts`, `year`, `month`, `guns`, `stolen`, `cargo.GOOD`, `relation.FACTION`, `captain.STAT_OR_SKILL`.

Faction words: `relation.X`, `war.X.Y`, `port_is.X` and the candidate key `at_war.X` also accept `port` (the port you're in), `home` and `marque`.

Yes/no: `council_member`, `council_leader`, `unrest_known`, `shares` (no prey, no pay), `port_is.FACTION`, `at_sea`, `in_port`, `storm`, `pirate`, `privateer`, `honest`, `wanted`, `pardoned`, `pardon_open.FACTION`, `war.A.B`, `flag.NAME`,
`contract.TEMPLATE`, `captain_trait.TRAIT`, `has_officer.POST`, `port_fence`, `true`.

Text: `date` (`"date >= 1715-07-31"`), `ship` (type), `port`, `port_faction`, `marque`, `home`.

## Outcomes

| Outcome | Effect |
|---|---|
| `gold +100`, `gold -10%` | Money |
| `crew +3`, `crew -2` | Recruits from the local mix, or random hands lost |
| `kill {r}`, `leave {r}`, `wound {r}`, `hire {r}` | One person (`kill captain` really kills the captain: someone else takes over) |
| `opinion {r} +5`, `opinion crew -3` | Their opinion of the captain |
| `relation spain -5` | Standing. Also `port` (this port's nation), `home`, `marque`, or a `{role}` holding a nation |
| `honour +2`, `fear +1`, `notoriety +3` | Reputation |
| `cargo rum +20`, `cargo {good} -all`, `loot silver 10`, `food +30`, `water -10` | Hold (`loot` marks it stolen) |
| `hull -15`, `sails -10`, `wages +50`, `paywages` | Ship and pay (`paywages` pays what you can of the back wages) |
| `skill {r} gunnery +1`, `trait {r} brave`, `untrait {r} drunkard`, `reveal {r}` | People change |
| `flag NAME [days]`, `unflag NAME` | Remember something for later events |
| `morale +10 30` | A morale modifier for 30 days, named after the event |
| `calm 3`, `expose`, `share +0.1` | Talk 3 plotters round; learn who leads the unrest; change the crew's share |
| `confidence`, `mutiny`, `depose` | A vote of confidence (lose it and you're out); the mutiny breaks now; the captain steps down |
| `favour {r} +1`, `secret KIND [{r} or any] [fake]`, `scandal {r}` | Favours (negative: you owe them); a secret (letters, ledger, bribes, schedule) about someone; an official recalled in disgrace |
| `influence PORT GROUP +5`, `stir 4`, `council_vote TOPIC yes/no`, `join_council` | Shift a port's interest groups; someone pays your crew to plot; the Nassau council votes (with your voice) |
| `abandon TEMPLATE` | Fails your active contract of that template (a double-cross, a bribe taken) |
| `event ID [delay] [window]` | Chain: queue another event, with the same roles, after `delay` days; it waits up to `window` days for its conditions |
| `fight KIND [faction] [mode]` | A battle: `merchant`, `pirate`, `navy`, `hunter`; mode `defend` (default), `attack`, `ambush`, `flee` |
| `market PORT shortage` | Starts a market event (`shortage`, `glut`, `bad_harvest`) |
| `time 3` | Days pass |
