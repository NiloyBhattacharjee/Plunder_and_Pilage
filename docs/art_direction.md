# Art direction: the engraved sea chart

The whole game should look like a hand-coloured chart and the engraved books of the period: Herman Moll's maps, the
Dutch atlases (Blaeu, Visscher), and the woodcut and copperplate illustrations in Exquemelin's *Buccaneers of America*
(1678) and Johnson's *General History of the Pyrates* (1724).

Rule of thumb: **ink first, colour second.** Every asset reads as black-brown line work on paper; colour is a thin
watercolour wash laid on top, the way colourists tinted engravings by hand.

---

## 1. Palette

Defined in `data/palette.json`; change it there and the whole game follows.

| Role | Colour | Use |
|---|---|---|
| Paper | `#ead9b0` (light `#f3e8cc`, dark `#d6c08e`) | All backgrounds, land, panels |
| Ink | `#3b2a1a` | All lines, text, hatching |
| Ink, soft | `#6b5640` | Secondary lines, faded text |
| Sea washes | deep `#b6c4ae`, shallow `#e2e3c8`, reef `#9fb39c` | Water only |
| Accent: wax red | `#8b2a1f` | Buttons, seals, headings, the red flag |
| Nation washes | England `#b8352c`, Spain `#d9a520`, France `#2f5fb3`, Dutch `#e07a1f`, Brethren `#222222` | Flags, port markers, small accents only. Always faded, never saturated fills. |

Washes should look slightly uneven, as if laid by brush, and never cover line work.

## 2. Line and hatching

- **Line weights** at the delivered size: outlines about 3 px, interior detail 1.5 px, hatching 1 px.
- **Shading is hatching, not gradients.** Parallel lines for light shade, cross-hatching for deep shade, stipple (dots)
  for soft surfaces such as faces, sails and sand. One consistent hatch angle per asset (about 45°) unless following form.
- **No soft airbrush, glow or lens effects.** Smoke and splashes are inky curls and dots.
- **Imperfection is fine.** Slight wobble in lines reads as hand-engraved.

## 3. Asset specifications

All PNG with transparency, sRGB. Paths are what the game loads (see `README.md`, Art); replace files at the same path.

### Ships (`assets/ships/<type>/`)
- Top-down, **bow pointing up**, centred on the canvas, which leaves room for sails across the beam.
- Six layers per ship, same canvas size, perfectly aligned:
  `hull.png`, `hull_damaged.png`, `sails_furled.png`, `sails_half.png`, `sails_full.png`, `sails_torn.png`.
- Delivered at **2x**: hull length sloop 96 px, schooner 104, brigantine 120, brig 128, fluyt 140, frigate 160,
  galleon 176, man-of-war 200. Canvas about 2.8 times the hull width wide and 1.15 times the length tall.
- Hull: planking and gun ports in line work, hatched shadow along one side. The damaged version adds shot holes,
  splintered rails and scorch hatching. Sails: stippled or lightly hatched canvas, with clear yards and booms.
  Square rigs show sails across the hull; sloops and schooners show fore-and-aft canvas along the centre line.
- **The flag is a separate file** (below); leave the stern clear for it.

### Flags (`assets/flags/`)
- 40 x 26 px (deliver 80 x 52 px if you like; the game scales). Ink border, flat wash colours.
- Current set: `england`, `spain`, `france`, `dutch`, `black` (Jolly Roger), `red` (no quarter), `white`.
  Later: personal flags for named pirate captains.

### Portrait parts (`assets/portraits/<layer>/`)
- 128 x 128 px, every part on the same canvas, aligned to the same face template (eyes at y about 53, chin at y about 86).
- Layers, bottom to top: background, body, head, wrinkles, eyes, nose, mouth, scar, facial_hair, hair, hat, eyepatch,
  accessory, tattoo, hook. The order lives in `data/portraits.json`.
- **Head, hair and facial-hair parts are drawn in ink on a near-white fill.** The game tints them by multiplying skin
  tone and hair colour, which works exactly like a colourist's wash over an engraving. Keep their shading as
  hatching, so it survives the tint.
- Clothing parts are tagged by role (crew, pirate, navy, merchant, captain, officer, governor, priest, official).
  Wound parts (eyepatch, scar, hook) and age (wrinkles) appear automatically from the story.
- Style: woodcut or engraved bust in three-quarter or straight-on view, like the frontispieces in Johnson's
  *General History*. Include women's clothing and hair (there are women captains and crew, and Anne Bonny and
  Mary Read) and a range of ethnicities true to the period's crews.

### Icons (`assets/icons/<category>/<id>.png`)
- 48 x 48 px, ink drawing of the object inside a thin round or cartouche frame, with at most one wash colour.
  Readable at 24 px.

### UI (`assets/ui/`)
- `panel.png`: tileable paper with an inked double border; 96 x 96 px, with about 10 px used as the nine-slice margin.
- Wax-seal buttons, tab ends, a title cartouche and dividers: drawn ornaments in the same ink.

### Map (`assets/map/`)
- The coastline is generated from Natural Earth data and drawn in code, so don't paint it.
- Wanted later: port glyphs (town, fortified town, fort, haven; per size), a cove marker, a few sea-monster and
  ship-in-full-sail vignettes for empty ocean, and a title cartouche. All ink with light washes.

### Effects (`assets/fx/`)
- Small greyscale textures, tinted in code: smoke curl, splash, splinter, flame, debris. 32 to 64 px.

## 4. Asset list and priorities

| Priority | Area | Count | Needed by |
|---|---|---|---|
| P1 | Ships, 8 types x 6 layers | 48 | now |
| P1 | Portrait parts (including women's options) | 75-90 | now (crew), milestone 8b (officials) |
| P1 | UI kit (paper, seals, tabs, cartouche, dividers) | about 12 | now |
| P2 | Flags | about 12 | milestone 5 (false flags), milestone 11 (rival pirates) |
| P2 | Icons: goods 18, traits 33, skills/stats 11, upgrades 13, posts 6, roles 4, ammo 3 | about 90 | as screens grow |
| P2 | Map glyphs and vignettes | about 15 | milestone 5-9 |
| P3 | Base building icons | about 11 | milestone 9 |
| P3 | Effects textures | about 6 | anytime |
| P3 | Event vignettes (engraved scenes) | about 20 | milestone 7, optional |

## 5. Commissioning

1. **Start with a paid test piece:** one ship (all six layers), one flag and ten portrait parts (a head, two eyes,
   a nose, a mouth, two hairs, a body, a hat). Drop them into the game at the right paths before committing to the rest.
2. **Brief to send:** this document, screenshots of the current placeholders, the exact file list with sizes, and
   two or three period references (below). Ask for layered source files (PSD, Krita, or SVG) as well as PNGs.
3. **Where to look:** ArtStation and Behance (search "engraving", "woodcut", "etching", "line art illustration"),
   r/gameDevClassifieds and r/HungryArtists, itch.io asset creators, and illustrators who do tabletop RPG maps.
   Vector line artists suit the ships and icons well.
4. **Licence:** a full commercial licence for the game, plus the right to modify. Add every delivered asset to
   `assets/CREDITS.md`.

## 6. Public-domain references (and possible sources)

These are out of copyright, and many museums publish their scans with no restrictions (check each scan's terms):

- Herman Moll, *A New Map of the West Indies* (early 1700s): lettering, cartouches, compass roses.
- A. O. Exquemelin, *De Americaensche Zee-Roovers* (1678) and its English edition *Bucaniers of America* (1684): buccaneer portraits.
- Captain Charles Johnson, *A General History of the Pyrates* (1724): engraved portraits of Blackbeard, Bonny, Read and Roberts.
- Dutch marine engravings by Wenceslaus Hollar and Reinier Nooms (Zeeman): ship line work and hatching.
- Sources: the Library of Congress, the Rijksmuseum (CC0 downloads), the John Carter Brown Library, the David Rumsey Map Collection.

Public-domain engravings can serve as reference or, after cleanup, as event illustrations, which would make the
optional P3 vignettes almost free. No AI-generated images go into the game.
