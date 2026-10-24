# Representing slavery and race

The Caribbean of 1650 to 1730 ran on slavery. Sugar islands grew rich on enslaved African labour, the asiento was a contract to sell people, and pirates both freed and sold the captives they found. The game shows this because leaving it out would be false. These rules say how. Every event, character, picture and mechanic that touches slavery or race follows them. A change that breaks one needs a reason written next to it.

## The one rule

Enslaved people are people with their own choices, never cargo, and never props in the player's story.

## Mechanics

- **No numbers on people.** No captives in the hold, no price per head, no market row, no ship stat or upgrade for carrying people. Where the game needs them in the world (plantation labour, the asiento's ships), it sits inside the economy model, not in the player's hands.
- **They choose.** When the player frees people, the player's choice sets up the scene; the freed people's choices end it. Some join under the articles, some ask to be put ashore, some head for the Maroons. Never "you freed them, +morale".
- **At least one of them has a name.** Use a `freed` role (`{"from": "new", "nation": "freed"}`), so one of them is a full character with traits, wants and opinions, not a crowd.
- **No reward for cruelty.** Selling captives pays, as it did. There's no achievement, perk, title or "dark path" for it. The cost comes through systems that already exist: crew opinion (especially from crew who were enslaved or whose people were), town memory (`PortLife.remember`), bonds, and who will still sail with you. No morality meter.
- **Freeing people isn't free either.** Planters, the asiento company and their governors remember it: bounty, closed ports, contracts against you. The consequences are real, and so is the cost.
- **Agency in the world.** Enslaved people resist without the player: plantation risings (`port_life.json` `revolt`), shipboard revolts, escapes, Maroon communities. They don't wait for a hero.

## Writing

- **Narration says "enslaved people", "captives", "the people in the hold".** A period character may say "slaves" where they would have. No slurs, ever, from anyone.
- **Don't blur indenture and slavery.** Indenture was a contract for years of labour, mostly of European servants, cruel but with an end, and it didn't pass to your children. Chattel slavery was for life and hereditary, and it was based on race. Treating them as the same thing is the "Irish slaves" myth, which is used to play slavery down. An indentured character can work beside enslaved people and know the difference. (The Escaped Indentured Servant background's story, `brand` in `data/stories.json`, was rewritten to this rule.)
- **Imply the violence, don't show it.** "The hold stank of four months at sea", not a description of suffering. Never for shock or flavour.
- **No saviour framing.** The captain doesn't get thanked into a hero. People can be grateful, wary, angry, or simply busy with their own plans.
- **Black characters everywhere, not only here.** Free Black sailors, quartermasters and gunners (some historians estimate a quarter or more of some pirate crews were of African descent), merchants in Willemstad and St Eustatius, free people of colour in Spanish towns, Maroon leaders. The `afro_caribbean` share in `rules.json` `people.recruit_mix` keeps them in every crew and tavern. Slavery content is not the only place they appear.
- **No he/she for role characters.** This applies to every event already; it matters doubly here.

## Art

- No caricatured features. African and Afro-Caribbean portraits get the same range of faces, ages, clothes and detail as everyone else (`data/portraits.json` `skin_tones.afro_caribbean`).
- No chained figures as scenery, decoration or background texture in painted scenes.
- A captain of African descent is possible in the character builder, with backgrounds written as carefully as the rest.

## Process

- **Sources:** Marcus Rediker, *The Slave Ship* and *Villains of All Nations*; the Trans-Atlantic Slave Trade Database (slavevoyages.org) for real ships, routes and dates; Olaudah Equiano, *The Interesting Narrative* for a first-hand voice; Mavis Campbell, *The Maroons of Jamaica 1655-1796*.
- **Sensitivity readers:** before release, paid readers, ideally Black readers who know Caribbean history, read every event that touches slavery or race. Drafts by the developer or Claude are only drafts until then.
- **Content note** on the new-game screen, and a history-notes page crediting these sources.

## Still to build

- **The Maroons as a faction** (planned in `brief_additions.md`, Addition 4).
- **A West African name and origin pool** for people taken off slavers, separate from `afro_caribbean` (Caribbean-born). The `freed` mix uses `afro_caribbean` until then.
- **A background for a captain who escaped slavery.** Not written yet; it needs a sensitivity reader before it goes in.
