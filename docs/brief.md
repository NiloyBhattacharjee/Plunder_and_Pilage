# Build a Caribbean piracy and trade game in Godot

You are helping me build a single-player piracy and trading game in Godot. I'm a software developer (Python, React, some Java) but new to Godot, so explain Godot-specific choices briefly when you make them. Work in milestones, and stop at the end of each one so I can run the game and give feedback before you move on.

## Design direction: deep, not wide

This is the most important part of the brief. I want deep gameplay, not a huge game.

- Fewer systems, but each one has real decisions and trade-offs. No system should be a menu you click through without thinking.
- Systems should feed into each other. For example: your base produces rum, rum keeps crew morale up, morale wins boarding fights, boarding captures ships, captured ships defend your base. A choice in one system should be felt in others.
- A smaller map with fewer ports, where each port has its own personality, governor, needs and history with the player. 12 to 15 ports that matter beat 40 that feel the same.
- Choices have consequences that come back later. NPCs remember what you did. Betraying an employer, sparing a crew, or sacking a town should change how the world treats you.
- Before adding anything new, ask: does this create a new decision for the player? If not, leave it out.
- When in doubt, cut breadth and add depth.

## Setting

- The Golden Age of Piracy, roughly 1650 to 1730.
- The map is the Caribbean: the Greater and Lesser Antilles, the Bahamas, the Gulf of Mexico coast, the Spanish Main and Central America.
- The coastline should be geographically recognisable. Use public domain coastline data (for example Natural Earth) or trace it by hand.
- Factions: England, Spain, France, the Dutch Republic, and the pirates/Brethren of the Coast. Each faction owns ports, has a navy, and has a relationship with the player.
- Core ports (12 to 15, each owned by a faction, with goods it produces and goods it wants):
  - England: Port Royal, Bridgetown, Basseterre
  - Spain: Havana, Santo Domingo, Cartagena, Portobelo, Veracruz, Maracaibo
  - France: Tortuga, Saint-Pierre
  - Dutch: Willemstad, St. Eustatius
  - Pirate havens: Nassau, plus a few small hidden coves the player can find
- Trade goods of the period: sugar, rum, molasses, tobacco, cotton, indigo, cocoa, hides, logwood, silver, gold, cloth, gunpowder, weapons, tools, wine. Do not include enslaved people as a trade good.

## Tech requirements

- Godot 4 (latest stable version), GDScript.
- Data-driven design. Ports, goods, ships, upgrades, crew types, contracts, base buildings and events live in data files (JSON or Godot Resources, explain which you pick and why), not hard-coded in scripts. I should be able to add a new ship, contract or event without touching code.
- A clear folder structure, for example `scenes/`, `scripts/`, `data/`, `assets/`, `ui/`.
- Save and load the full game state to a file.
- Placeholder art (simple shapes, free CC0 assets) at first. Keep art swappable.
- Small, focused scripts with short comments where logic isn't obvious.
- Automated tests for core logic (economy, combat maths, event conditions, base production, siege resolution) using GUT or a simple test scene.

## Core systems

### 1. World map and sailing
- Top-down map. The player's ship sails in real time (with time acceleration), clicking to set a course.
- Wind with direction and strength that changes over time. Ships sail faster on some points of sail and slow badly when heading into the wind.
- Time passes in days. Food, water and wages are used up each day.
- Weather: calm, fair, storms, and a hurricane season (roughly June to November).
- Shallow waters and reefs: shallow-draught ships can use them to escape bigger ships.
- Other ships sail the map: merchants on trade routes, navy patrols, pirates, pirate hunters, and rival captains.

### 2. Economy and trade
- Each port has buy and sell prices based on what it produces and wants.
- Prices drift over time, react to the player's trading, and respond to events (shortages, blockades, war).
- The player only sees current prices in the port they're in. For other ports they see the last prices they saw, with how old they are.
- Smuggling: some goods are illegal in some ports. Selling them pays more but risks fines and reputation loss.
- Fences: stolen cargo sells cheaply in legal ports (or not at all), but at full price through fences in pirate havens and your own bases.

### 3. Career paths: privateer, pirate, or both
The player's legal status is a core part of the game, not a label.

- **Privateer:** holds a letter of marque from one faction. Can legally attack that faction's enemies. Must hand over a cut of prizes to the Crown. Gets access to that faction's ports, shipyards and contracts. Gains rank with the faction (for example: privateer, commodore, eventually a governorship).
- **Pirate:** attacks anyone and keeps everything. Hunted by every navy. Crew run things more democratically: they vote, expect fair shares, and can depose the captain. Access to pirate havens, fences and pirate contracts.
- **Switching sides has consequences.** When factions sign peace, letters of marque are cancelled and privateers who keep raiding become pirates. A pirate can take a royal pardon, but old crew may resent it and old enemies remember. Betraying a faction you sailed for makes a permanent enemy.
- Also possible: honest merchant, smuggler, or pirate hunter. These should be viable but the focus is privateers and pirates.

### 4. Contracts
Contracts are the main source of structured missions. Each one has an employer, reward, deadline, risk, and effects on reputation. Some employers lie, and some contracts are traps.

- **Privateer contracts** (from governors and admiralty officers): raid an enemy's shipping in a region, capture a specific named ship, blockade a port, escort a convoy, carry secret dispatches, hunt a pirate captain, attack an enemy fort or town.
- **Pirate contracts** (from fences, haven bosses, brokers and shady merchants): hijack a specific cargo, kidnap and ransom a noble, take revenge on a rival captain, smuggle contraband past a blockade, break prisoners out of a fort, steal the sailing schedule of a treasure fleet, sink a pirate hunter.
- **Consequences:** contracts have side effects. Raiding Spanish shipping for England angers Spain. A contract's target may have friends. Failing or abandoning a contract damages your name with that employer.
- **Contract chains:** an employer who trusts you offers bigger, riskier jobs over time.

### 5. Bases and base management
The player can own bases, which act as home, income source and staging point. Keep the number small (3 to 5 bases maximum) so each one gets real attention.

- **First base:** a hidden cove found through exploration or an event. Starts as a careening beach and a hideout.
- **Buildings** (each with a cost, build time, upkeep and a real effect): dock, careening yard, warehouse, tavern (recruits and morale), shipyard (repairs, later builds ships), battery and fort (defence), watchtower (early warning, reveals nearby ships), plantation or distillery (produces goods), smugglers' market (sells stolen cargo at full price), stockade (holds prisoners for ransom).
- **Management:** assign an officer to run each base. Their skills affect income, defence and loyalty. Bases need supplies, a garrison and money for upkeep.
- **Threats:** bases can be discovered. A base's visibility rises with activity. Navies, pirate hunters and rivals can raid it, and the player must defend it, either by being there or by having enough defences and garrison.
- **Base as part of the loop:** bases produce goods you sell, store plunder safely, repair ships cheaply, recruit crew, and hold captured ships.

### 6. Taking over bases
The player can capture other bases: pirate havens, small colonial towns and forts. Not the biggest capitals at first.

- **Ways to take a base:** naval bombardment of its fort, a land assault with marines, a blockade to starve it out, a night raid, bribing the garrison, or helping a local uprising. Each has different costs and risks.
- **Siege phases:** scout the defences, deal with the fort and any ships, land troops, resolve the assault. Keep it simple but with real decisions (how many men to land, which side to attack, whether to wait for reinforcements).
- **After capture:** sack it (big loot, huge reputation hit, town is ruined), ransom it back, or hold it as your own base. Holding it means garrisoning it, and its former owner will send expeditions to retake it.
- **Pirate havens** can also be taken over by defeating or replacing the current boss, through a duel, a vote of the captains, or force.

### 7. Ship types
Each ship type has its own strengths and weaknesses. Stats: hull, sails, speed, turning, sailing into the wind, cargo, crew capacity, gun slots, draught, price and upkeep.

| Ship | Strengths | Weaknesses |
|---|---|---|
| Sloop | Fast and nimble, shallow draught, classic pirate ship | Light hull, limited cargo |
| Schooner | Very good into the wind, small crew needed | Few guns, moderate cargo |
| Brigantine | Good balance of speed, guns and cargo | Master of none |
| Brig | Solid warship for its size | Needs a big crew, poor into the wind |
| Fluyt | Huge cargo, cheap to run | Slow, barely armed |
| Frigate | Fast for its firepower, strong all-rounder warship | Expensive, needs a big crew |
| Galleon | Massive hull and cargo, many guns | Slow, turns badly, deep draught |
| Man-of-war | Most firepower in the game | Very slow, very expensive, can't enter shallow water, navy only until late game |

- Ships can be bought (not every port sells every type), captured, sold, and later built at your own base.
- The player can run a small fleet of up to 3 to 5 ships, with officers as captains of the others.

### 8. Ship upgrades
Every upgrade has a trade-off:
- Copper sheathing: faster, slower to foul, expensive
- Reinforced hull: more hull, slower
- Extra sails / better rigging: faster, needs more crew
- Cannon weight (4 to 24 pounders), swivel guns, chase guns
- Expanded hold: more cargo, fewer gun slots
- Better quarters: higher crew morale, less cargo
- Ships slowly foul and lose speed until careened. Hull and sails take damage and need repair.

### 9. Captain
- Name, nationality, starting background (ex-navy officer, merchant's son, escaped indentured servant, disgraced privateer). Background sets starting stats, money and faction relations.
- Skills that improve with use: Navigation, Gunnery, Swordplay, Leadership, Trade, Seamanship.
- Reputation with each faction, plus a separate notoriety score and a personal reputation (feared, respected, honourable, ruthless) built from how you treat prisoners, crews and employers.
- The captain is a crew member like any other (see Crew), with the same leadership stats and traits, so the player character can be replaced.

### 10. Crew as individuals
Every crew member is an individual with a name, stats, traits and a history. The UI should not force the player to manage hundreds of people one by one. Show the crew as a group (counts, average morale, problems) and highlight the notable individuals: officers, troublemakers, rising stars and possible successors.

**Leadership stats** (for every crew member, including the captain):
- **Authority:** how much the crew accepts their orders. Grows with rank, victories and fair dealing.
- **Experience:** years at sea and battles survived. Improves their job and how others respect them.
- **Intimidation:** ruling by fear. Stops trouble quickly but breeds resentment.
- **Charisma:** being liked and persuasive. Wins votes, calms disputes, recruits better men.

**Job skills:** sailing, gunnery, fighting, plus officer skills (navigation, carpentry, medicine, trade).

**Traits** (each crew member has 1 to 3, some can be gained or lost over time). Each trait should change behaviour in a real way. Examples:
- Loyal, ambitious, greedy, cowardly, brave, bloodthirsty, superstitious, drunkard, gambler, honest, schemer, devout, veteran, green, hot-headed, calm, popular, hated, sea-legs, seasick, former navy, family man.
- Traits interact: a greedy schemer with high charisma is the classic mutiny leader; a superstitious crew panics during a bad omen event; a bloodthirsty crew resents a captain who spares prisoners.

**Relationships:** crew members form friendships, rivalries and factions within the crew. A popular officer's death hurts morale; two rivals on the same ship cause fights.

**Recruiting:** in taverns and your own bases. Availability and quality depend on the port, your reputation and pay. Recruits can be interviewed briefly, and some hide their traits until they show up at sea.

**Other crew mechanics:**
- Crew roles: sailors, gunners, marines, each improving a different part of the ship.
- Officers (Quartermaster, Navigator, Master Gunner, Boatswain, Carpenter, Surgeon) are chosen from your crew or hired. Officers can captain other ships or run bases. Disloyal officers can betray you.
- Morale: affected by pay, food, rum, victories, losses, plunder shares and how the captain behaves (does it match what the crew values?).
- Pirate articles: as a pirate, set the shares and rules. Crew vote on big decisions.
- Disease if food and water run low or voyages are long.

### 11. Mutiny
Mutiny should build up over time and be visible to the player, not appear out of nowhere.

- **Discontent** grows from low pay, hunger, losses, harsh punishments, broken promises, and captain choices that go against the crew's traits (sparing prisoners on a bloodthirsty crew, raiding for a Crown the crew hates).
- **Ringleaders** emerge: crew with high charisma or intimidation and traits like ambitious, greedy or schemer gather supporters. Loyal officers or informants can warn the captain.
- **Warning signs** through events: grumbling, a round robin (a petition with names in a circle so no one is the leader), stolen weapons, a black spot.
- **Captain responses,** each with consequences: pay out, make promises, punish (flogging, marooning, hanging) using intimidation, talk them down using charisma, put the ringleader ashore, give in to demands, or call a crew vote.
- **The mutiny itself:** resolved from the support each side has, officer loyalty, and the leaders' stats. Outcomes: mutiny crushed, captain deposed and put ashore or marooned, captain killed, crew splits and some take a ship, a negotiated deal.
- Fleet mutinies: an officer captaining another of your ships can go rogue and become a rival.
- Bases can also rebel if their garrison or manager is unhappy.

### 12. Captain death and succession
The captain can die: in combat, boarding, duels, disease, storms, hanging, or mutiny.

- **If the crew is strong, the story continues.** When the captain dies (or is deposed), the crew picks a new leader from among themselves, and the player continues as that person.
- **How the new leader is chosen** depends on the ship's culture:
  - Pirate crews hold an election. Candidates are the crew with the highest authority, charisma and experience. The player can see the candidates and their support, and influence the vote if the player was building up a successor beforehand.
  - Privateer or navy-style crews follow the chain of command: the Quartermaster or most senior officer takes over, unless the crew rejects them.
  - Someone with high intimidation can seize command by force, which starts their captaincy with low morale.
- **What carries over:** ships, bases, money held by the crew, faction reputation (partly), contracts (some employers won't trust the new captain), rivals and flags from events. The new captain brings their own stats, traits and relationships, which changes how the crew behaves.
- **Building a legacy:** the player should be encouraged to develop good officers and a possible successor, because a crew of nobodies may fall apart, scatter or turn on each other when the captain dies.
- **Game over** only happens when there is no one to take over: the whole crew is lost, or the crew breaks up with no leader. Ironman mode makes this permanent.
- The ship's log records the line of captains, so a long game becomes a dynasty of pirate captains.

### 13. Combat
- Naval combat as its own scene: ships manoeuvring with wind, firing broadsides.
- Ammunition: round shot (hull), chain shot (sails), grape shot (crew).
- Damage to specific parts: masts, rudder, gun decks, hull below the waterline.
- Boarding resolved from crew numbers, marines, morale, officers and the captain's Swordplay, with a few decisions during it (push, hold, target the captain).
- After winning: take cargo, capture the ship, ransom or recruit prisoners, or let them go. Each choice affects reputation.
- Fleeing and surrendering are always options for both sides.

### 14. Event system
I want a large set of random events, eventually around 1000. Build it in two parts:

1. **The engine.** Events are data. Each event has: id, title, text, conditions (location, date, career path, faction relations, notoriety, ship type, cargo, crew morale, mutiny risk, traits and stats of the captain or specific crew members, bases owned, flags from earlier events), weight, and 1 to 4 choices. Choices can have their own conditions, a skill check, and outcomes (gold, crew, morale, reputation, cargo, ship damage, start a fight, give an item, set a flag for later events). Support event chains.
2. **The content.** Write the first 100 to 150 events by hand, using templates with variables (port, faction, good, ship name, officer name) so each event can appear in many forms. Design the format so I can add more in batches until I reach 1000.

Event categories: at sea, crew (including events driven by individual crew traits and relationships), mutiny warning signs and confrontations, succession and elections, port, faction and politics (historical wars like the War of the Spanish Succession, the 1718 King's Pardon), economy, treasure, bases (raids, discoveries, officer problems, production), contracts (betrayals, double-crosses), and historical figures of the era (Henry Morgan, Blackbeard, Bartholomew Roberts, Anne Bonny, Mary Read, Calico Jack).

## Extra features (only if they add depth)
- **Rivals:** a few named NPC captains who grow over time, remember you, and come back for revenge or offer alliances.
- **Bounties:** a price on your head that attracts pirate hunters. Named pirates have bounties you can collect.
- **Treasure maps:** found in events or bought, sometimes fake.
- **Living world:** factions go to war and make peace over time, ports change hands, trade routes move.
- **Ship's log:** a journal that records your story, including the line of captains, and can be read back.
- **Endings:** retire rich, become a governor, rule a pirate republic, hanged, die at sea.
- **Difficulty settings** and an optional ironman mode.
- **Tutorial:** a short first voyage that teaches sailing, trading and combat.

## Milestones (stop after each one)

1. Project setup, folder structure, data format, Caribbean map with ports, sailing with wind and time passing.
2. Ports: market trading, shipyard, tavern. Save/load.
3. Ship types, upgrades, and the crew member data model (stats, traits). Build the captain on this same model from the start, so succession works later without a rewrite.
4. Naval combat and boarding, prizes.
5. Factions, reputation, career paths (privateer and pirate), letters of marque, pardons, NPC ships on the map.
6. Contracts system with the first set of privateer and pirate contracts.
7. Event engine plus the first batch of events.
8. Crew as individuals: stats, traits, relationships, officers, morale, articles, disease. Then mutiny, captain death and succession.
   - 8b. Political intrigue (see `brief_additions.md`, Addition 1).
   - 8c. Alliances and rivalries (Addition 2), if 8b gets too big.
9. Bases: finding a cove, buildings, management, raids on your base.
10. Taking over bases: sieges, capture, sack/ransom/hold, retake expeditions.
11. Rivals, bounties, treasure (rivals and bounties use the alliance/rivalry system from 8b/8c).
12. Balancing, polish, tutorial, endings.

After each milestone, report which systems now connect to each other and where the gameplay still feels shallow.

## Note from the user
Inspiration: the Paradox games (EU4, CK3 style): tooltips that explain numbers, map modes, pausable time, moddable data, character-driven play.
