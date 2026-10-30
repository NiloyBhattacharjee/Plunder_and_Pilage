# Additions to the game brief

This file adds to `brief.md`. Read that first. Everything here follows the same rules, especially "deep, not wide": new features should reuse existing systems and create real decisions, not add separate screens or mini-games.

---

## Addition 1: Political intrigue

### Goal
Politics in the Caribbean should feel alive and personal. Ports aren't just owned by a nation. They're run by people with their own ambitions, rivals, secrets and debts, and the player can use that or get caught up in it.

### Rule for building it
Do not build a separate diplomacy system. Political intrigue must come out of the systems that already exist:
- Political characters use the **same character model as crew members** (Authority, Experience, Intimidation, Charisma, traits, relationships).
- Political jobs are **contracts**.
- Political twists are **events** with conditions and flags.
- Political standing feeds into **reputation**, **career paths** (privateer/pirate), **bases** and **taking over bases**.

### 1. Officials and power brokers are characters
- Each port has a governor, plus a few other key figures: a harbour master, a garrison commander, a wealthy merchant or planter, a priest, a fence or smuggler boss.
- They use the shared character model, with political traits such as: corrupt, ambitious, pious, cowardly, honest, vengeful, secretly in debt, drunkard, reformer, loyal to the Crown, sympathetic to pirates.
- Each one has goals (get rich, get promoted, crush piracy, protect their trade, get revenge on a rival) and acts on them over time.
- They have relationships with each other and with the player: allies, rivals, debts, grudges.
- Officials change. Governors can be recalled, promoted, die of fever, be killed, or be replaced, so the political map shifts during the game.

### 2. Factions inside each nation
- Each colony has internal interest groups, for example: planters, merchants, military, church, and the town's poorer folk.
- Each group has influence over the governor. The group with the most influence shapes the port's laws: tariffs, banned goods, how harshly pirates are treated, whether pardons are offered, how much the navy patrols.
- Working for one group raises its influence and annoys the others. The player can deliberately shift who holds power in a port.
- Pirate havens have their own internal politics (see section 7).

### 3. Information as a resource
- Secrets are items the player can hold: a governor's private letters, a merchant's smuggling ledger, a treasure fleet sailing schedule, proof an admiral takes bribes, a list of a rival captain's hideouts.
- Ways to get them: captured ships, raids, tavern informants, bribed clerks, events, officers with the right skills or traits.
- What to do with them, each with consequences:
  - Blackmail the person (ongoing favours, but they may try to get rid of you)
  - Sell the secret to their rival
  - Hand it to the Crown or a faction for reputation
  - Keep it as insurance
  - Use it to trigger an event (a scandal, an arrest, a recall)
- Secrets can go stale (the fleet already sailed) or be fakes planted to trap the player.

### 4. Favours and debts
- Characters can owe the player favours, and the player can owe them.
- Favours are tracked like a currency but tied to a specific person.
- Calling in a favour can unlock things gold can't buy: a pardon, a warning about a navy patrol, a blind eye in port, a vote.
- NPCs call in favours too, often at bad times (for example: sink a ship belonging to someone you like). Refusing damages the relationship and may make an enemy.

### 5. Schemes
Schemes are multi-step political plots, built as contract or event chains with flags. The player can start them, and NPCs run their own.

Player schemes, for example:
- Frame a rival captain so the navy hunts them
- Ruin a governor so a friendly one replaces them
- Push two nations toward war so letters of marque become more valuable
- Stir up unrest in a town before attacking it
- Work as a double agent for two factions
- Smuggle a political exile to safety, or hand them over

NPC schemes:
- Rivals and officials run plots that can target the player: setting a trap with false information, turning one of the player's officers, bribing the crew, framing the player for a crime.
- Give the player chances to discover these through informants, loyal officers, suspicious events or captured letters, and to respond.

Each step of a scheme should be a real decision, with a risk of failure and of being found out. Being caught should have lasting consequences.

### 6. Links to existing systems
- **Crew:** officers with high Charisma or schemer/ambitious traits are useful for intrigue, but are also the ones most likely to betray you. Political enemies may try to turn your officers or fund a mutiny.
- **Succession:** a new captain inherits some political relationships but not all. Some officials only trusted the old captain.
- **Career paths:** privateers depend on staying in favour with their faction's politicians. A change of governor can cancel a letter of marque or upgrade it.
- **Contracts:** most political actions are delivered as contracts from officials and interest groups.
- **Bases:** owning a base makes you a political player. Officials may tolerate it, tax it, try to take it, or ask you to use it for their schemes.
- **Taking over bases:** political groundwork (bribing the garrison, winning over a faction, weakening the governor) makes capturing a town easier and holding it more stable.

### 7. Pirate politics
- Pirate havens like Nassau are run by a council of pirate captains (NPC characters with stats, traits and fleets).
- The council votes on big decisions: accept a royal pardon, defend the haven against the Crown, who leads, whether to punish a captain who broke the code.
- The player can join the council once they have enough notoriety, then buy votes, form alliances, trade favours, or challenge the leader.
- Winning control of the council is another way to take over a pirate haven (alongside force and duels).

### 8. Historical anchors
Real events shift the balance of power at fixed dates, and the player's choices change how they play out:
- War of the Spanish Succession (1701 to 1714): England and the Dutch against France and Spain. Letters of marque are easy to get.
- Treaty of Utrecht (1713): the war ends, privateers are suddenly out of work, and many turn pirate.
- The King's Pardon (1718): pirates are offered amnesty for a limited time.
- Woodes Rogers arrives as governor of the Bahamas (1718) to clean up Nassau.
- Use these as event anchors with branching outcomes, not as fixed cutscenes.

### 9. UI
- A simple "people" view: known characters, their role, port, faction, how they feel about you, known traits, and favours owed either way. Unknown traits show as "unknown" until discovered.
- A "secrets" list in the player's inventory.
- Port info shows who holds power and the current laws.
- Keep it light. Most intrigue should happen through dialogue, contracts and events.

### Milestone
**Milestone 8b: Political intrigue.** After the crew milestone and before bases. Officials and power brokers using the shared character model, interest groups and their influence on port laws, secrets, favours, the first set of political contracts and schemes, NPC schemes against the player, and the Nassau pirate council. Historical anchors can be added with the event content.

After the milestone, report which existing systems the intrigue now connects to and where it still feels shallow.

---

## Addition 2: Alliances and rivalries

### Goal
The player can form alliances and rivalries with NPC captains, pirate havens, factions and political figures, but never has to. Every alliance and every rivalry must come with real benefits **and** real costs, so choosing a side is always a trade-off. Staying neutral is also a valid choice with its own pros and cons.

### Rule for building it
Same as Addition 1: build this from existing systems. Alliance and rivalry partners use the shared character model, relationships are tracked like the existing reputation and favour systems, and most of the play happens through contracts, events and combat.

### 1. Who you can ally with or be rivals with
- **NPC captains** (including the named rivals from the main brief)
- **Pirate havens** and their councils
- **Factions** (England, Spain, France, the Dutch), beyond simple reputation
- **Political figures** and interest groups (from Addition 1): a governor, the planters of a colony, a merchant house
- **Your own former officers** who left to captain their own ships

### 2. Alliances
Levels of commitment, each with stronger benefits and stronger obligations:
1. **Understanding:** you agree not to attack each other.
2. **Pact:** you share information and trade at better prices.
3. **Alliance:** you fight together, share bases and split plunder.
4. **Sworn brotherhood** (pirates) or **patronage** (officials): the deepest tie, very hard to break without huge consequences.

**Benefits** (examples): an ally's ships join your battles, sieges or base defence; shared intelligence (secrets, sightings, patrol routes); access to their ports, bases, fences, shipyards and crew pools; better contracts and prices; political backing (council votes, protection from a governor); safety in their waters.

**Costs** (examples):
- **Obligations:** allies call for help, sometimes at bad times. Ignoring the call damages the alliance.
- **Their enemies become your enemies.**
- **Shared loot:** joint raids mean splitting plunder.
- **Reputation drag:** a butcher ally's reputation rubs off. Crown allies make pirate crews uneasy; pirate allies make the Crown suspicious.
- **Crew reaction:** crew with certain traits may hate an ally, hurting morale and feeding mutiny.
- **Dependence:** an ally who knows your base or secrets can hurt you badly if they turn.
- **Betrayal risk:** ambitious, greedy or schemer allies may betray you if it pays enough, or if your power drops.

### 3. Rivalries
Rivalries start from events (you sank their friend, took their contract, beat them in a vote), are declared on purpose, or are inherited (a new captain inherits the old captain's rivals).

Levels: 1. **Competition** (race for the same contracts and markets), 2. **Feud** (open hostility, attacks on sight, sabotage), 3. **Blood feud / vendetta** (they will spend everything to destroy you, and you them).

**Benefits:** fame for beating a known rival; bounties paid by factions; crew unity against a shared enemy; taking their territory, contracts, bases and routes; their enemies become potential allies.

**Costs:** ambushes, base raids, attacks on your trade; sabotage (bribing officials, rumours, raising your bounty, turning officers, funding mutiny); contract competition; rising prices or closed doors where the rival has influence; time and resources spent on the feud.

### 4. Neutrality
- **Benefits:** trade and work with anyone, no obligations, no inherited enemies.
- **Costs:** no backup, fewer top-tier contracts, less political influence, and some NPCs see a neutral captain as an easy target.

### 5. How relationships change
- Relationships move with actions, events, favours and broken promises.
- Rivalries can become alliances (common enemy, debt paid) and alliances can become rivalries (betrayal, broken promise, loot dispute).
- NPCs remember. Betraying an ally affects how every character trusts you.
- NPCs form alliances and rivalries with each other, so the world shifts even if the player stays out.
- Breaking an alliance on purpose costs more at higher levels (a broken sworn brotherhood is remembered by every pirate in the Caribbean).

### 6. Links to existing systems
- **Political intrigue:** alliances with officials and interest groups are how the player gains lasting political power. Rivals run schemes against the player.
- **Crew and mutiny:** crew traits react to who you ally with and fight. Rivals may try to start a mutiny.
- **Succession:** a new captain inherits alliances and rivalries, but allies may reconsider.
- **Bases:** allies can garrison or defend your bases. Rivals target them.
- **Taking over bases:** allied fleets join sieges. Rivals may hold the bases you want.
- **Contracts and events:** alliance requests, betrayals, calls for help and rivalry escalations come as contracts and events.

### 7. UI
- Show alliance and rivalry status in the "people" view, with the level, what each side owes the other, and recent history.
- Before forming or breaking a relationship, show the expected benefits and costs clearly, including whose relationships will change as a result.

### Milestone
Build with Addition 1 in **Milestone 8b**, or straight after as **Milestone 8c** if 8b gets too big. Basic rivals and bounties from milestone 11 should use this system rather than a separate one.

After the milestone, report how alliances and rivalries connect to other systems and where the trade-offs feel weak or one-sided.

---

## Addition 3: Art pipeline

### Goal
Solo developer, not an artist. Art should look good and stay consistent, relying on code and simple layered assets instead of large amounts of hand-drawn art. Build the systems from the start so art can be swapped or restyled without changing game code.

### General rules
- **Placeholders first.** Simple shapes and free CC0 assets (e.g. Kenney.nl) until gameplay works. No final art before milestone 4 or 5.
- **Everything swappable.** Code refers to art through data (ids and paths in data files), never hard-coded paths. Changing a sprite or portrait part = replacing a file.
- **One style everywhere.** Working direction: **old sea chart look**: parchment and ink map, ships as small drawn icons, paper-textured panels, period fonts. Colours and line styles live in one shared place (a Godot Theme plus a small palette file).
- **Track licences.** Asset manifest (`assets/CREDITS.md`) listing every third-party asset, source, author and licence. Commercial-use licences only.

### 1. Procedural map
- Built from Natural Earth (public domain) via a Python preprocessing tool (clip, simplify, project, export).
- Land as Polygon2D, coastlines as Line2D style, with: a water shader (subtle waves, darker deep water, lighter shallows and reefs), parchment overlay, ink coastlines (maybe hatching), optional lat/long grid and compass rose.
- Ports stored as real lon/lat, projected the same way.
- Shallows, reefs and hidden coves are data on top of the map, for gameplay and drawing.
- Support fog of war / uncharted areas (faded or blank parchment) for later exploration.

### 2. Ships
- One top-down sprite per ship type, rotated in code, with separate layers: **hull** (damaged versions or overlay), **sails** (furled, half, full, torn), **flag** (per faction, black flag, red flag, false flags; flags are gameplay).
- Optional later: Blender models rendered top-down into sprites; folder structure should allow replacing hand-made sprites without code changes.
- Combat may use larger versions of the same sprites.

### 3. Layered character portraits
- Layers: background, body/clothing, head, skin tone, eyes, nose, mouth, hair, facial hair, hat, accessories (earring, eyepatch, hook), scars, tattoos.
- Parts per layer defined in data, with tags (navy coat, merchant clothes, pirate, governor's wig, priest) so portraits match role and nationality.
- **Each character stores a portrait seed** (plus fixed choices) so the same face rebuilds after loading.
- **Portraits change with the story:** scars/eyepatch/hook when wounded, ageing (grey hair, wrinkles), clothing changes with rank or wealth.
- Start with placeholder parts; 40-60 parts give thousands of faces.

### 4. Icons and UI
- Icons for goods, buildings, traits, skills, upgrades, loaded by id from data; one consistent family.
- One Godot Theme: parchment panels, ink borders, wax-seal buttons, period fonts from Google Fonts (IM Fell English for text, Pirata One for titles). Body text must stay readable; decorative fonts for headings only.

### 5. Effects
- Godot particles for cannon smoke, muzzle flashes, splashes, fire, sinking, storm rain. Small and consistent with the chart style (inky smoke).

### 6. AI-generated art
- Not as final game assets. Concept/mood reference only, outside the game files.

### 7. Folder structure
`assets/map/`, `assets/ships/<ship_type>/`, `assets/flags/`, `assets/portraits/<layer>/`, `assets/icons/<category>/`, `assets/ui/`, `assets/fx/`, `tools/`.

### Milestones
- **M1:** procedural Natural Earth map, asset manifest and folder structure.
- **M3:** layered portrait system with placeholder parts; portrait seed on every character.
- **M4:** ship sprites with separate hull, sail and flag layers; basic combat effects.
- **Around M5:** stop and help choose the final art style; list the assets needed with rough counts (make, buy or commission).

---

## Addition 4: The Golden Age, simulated

### Goal
Simulate the Golden Age of Piracy accurately, and show it the way Paradox does: a ledger of charts the player can read. Being accurate means three things: model the forces that caused the period, tune the model against real numbers, and check it with the headless sims.

### Steps (stop after each one)
1. **The Ledger.** A `Stats` autoload records a weekly snapshot (saved with the game); one `Chart` control (a `_draw()` control like `ui/price_spark.gd`: lines, stacked areas, bars, hover tooltips) draws it. Tabs: Economy (price index per port, trade volume, your income and costs), Opinion (faction standing, town regard, crew mood, with markers for the events that moved them), The Sea (pirates at large, navy strength, the price on your head, wars as bands). History events are marked on every chart.
2. **Pirates as a population, and the navy's answer.** Pirates at sea grow with out-of-work sailors (a jump after every peace, Utrecht most of all) and mutinies, and shrink with pardons, hangings and death. That number drives pirate spawns and merchant losses. Merchant losses push insurance up and bring more navy station ships and hunters, so the Golden Age ends because of what pirates did, not because of a date.
3. **Real captains.** (Built: `data/captains.json`, `Bonds.history_day`.) Hornigold, Blackbeard, Vane, Rackham, Bonny and Read, Bellamy, Roberts, La Buse appear on their real dates from their real bases, through the roster-captain system, and keep to their histories only if you don't get in the way.
4. **Living towns and the Maroons.** (Built: `scripts/economy/towns.gd`, `scripts/maroons.gd`, `data/events/maroons.json`.) Port populations change (fever, sugar booms, arrivals). Slavery sits in the economy as plantation labour and the asiento's ships, never as a market good; follow `docs/representation.md`. The **Maroons** are a faction in the hills of Jamaica and Hispaniola: people who escaped slavery and fought for their freedom. You can trade with them, ally with them, land freed captives with them, or betray them to the governor, through the existing faction, bond and event systems.
5. **Calibration.** `data/calibration.json` lists historical targets with sources (pirate numbers by year after Rediker, Nassau 1713-1718 after Woodard, sugar prices, treasure fleet sizes). `tools/balance_sim.gd` runs many seeds and prints simulated against historical numbers; the same charts plot them.
