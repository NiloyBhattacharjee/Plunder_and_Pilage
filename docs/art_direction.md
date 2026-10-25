# Art direction: HD-2D pixel art (the Octopath Traveler look)

Since 2026-10-16 the game follows the look of *Octopath Traveler II*: pixel-art sprites in a lit 3D world, with
soft glow, a tilted camera and a shallow depth of field, and windows of navy glass with gold trim. Before that it
was an engraved sea chart. The chart survives as the world map, now drawn in pixels.

Rule of thumb: **pixels are the material, light is the paint.** Sprites stay flat and crisp (nearest-neighbour,
whole-number scales, small palettes); depth, mood and drama come from real-time light, haze and blur.

---

## 1. Where each look lives

| Part | How | Files |
|---|---|---|
| Battles | A 3D diorama (`scripts/combat/battle_stage.gd`): pixel ships as `Sprite3D`s standing in a pixel-shaded sea, a sky that follows the time of day, glow, fog, a tilt-shift depth of field, muzzle flashes and fires that light the ships, lanterns at dusk, rain in storms | `assets/ships_side/`, `assets/battle/` |
| World map | HD-2D in 2D: a pixel sea like the battle's (depth colours, reefs, rolling surf, swells, sun glints), land lit as relief from a height map and painted as pixel art (speckled grass, a dark forest floor, cracked rock, grey peaks, dithered light), with some 24,000 upright pixel trees standing on it (`scripts/tree_layer.gd`: palms on the coasts, jungle inland, pines up high, lifted with their hills), drifting clouds and their shadows, day and night from the clock (a CanvasModulate tint, port towns and your lantern light up at dusk), wakes behind ships, little pixel towns for ports. Everything snaps to a grid of art pixels in world space (`palette.json` `map_pixel`), so it's crisp zoomed out and chunkier zoomed in, with no screen-wide filter to blur it. Port names sit on their own layer so the night never dims them. Seen as a diorama from a camera tilted toward the north: the 2D camera squashes the ground north-south (`Geo.TILT`), towns, names and icons are drawn upright under `Geo.UPRIGHT`, the land shader traces each pixel's ray against the height map so hills really rise (`hill_height`), and a tilt-shift layer blurs the top and bottom of the view with a little haze to the north | `assets/map/sea.gdshader`, `land.gdshader`, `paper.gdshader` (clouds), `tilt_shift.gdshader`, `height.png` (`tools/make_heightmap.py`), `trees.png` (`tools/make_map_trees.py`), `town.png` |
| Windows and menus | 9-slice pixel frames, built into the Theme by `scripts/style.gd` | `assets/ui/pixel/` |
| Portraits | HD pixel-art busts, 96x96, layered (background, clothes, head, eyes, nose, mouth, hair, beard, hat, and the marks a life at sea leaves). Skin and hair are drawn in grey ramps and tinted per character. Clean bands of shading with a thin seam of dither where they meet, a dark outline, light from the upper left. Drawn crisp when shown large, smoothed when shrunk into a small chip. Pirate types to start from (`portraits.json` `presets`) | `assets/portraits/` (`tools/make_pixel_portraits.py`) |
| Top bar icons | 16 px pixel icons scaled x3 | `assets/icons/hud/` |
| Painted scenes | 800x450 pictures, shown x2 behind the port screen (with mouse parallax, the hour's tint and lit windows at night, after an opening shot with the town's name) and x1 above a dialog's text, cropped to the middle band. Each port has its own (`port_<id>`, drawn from its tags and nation); events, sightings, sieges and endings point to theirs in `data/scenes.json`, and an event in port shows the port's. A scene is a folder: `back.png`, optional `front.png` (shifts more) and `lights.png` (added on from dusk). `ui/scene_view.gd` shows them | `assets/scenes/` (`tools/make_scenes.py`) |

## 2. Palette and fonts

`data/palette.json`. UI colours are the plain names: navy glass (`parchment` = window, `parchment_light` = raised,
`parchment_dark` = deep), off-white text (`ink`), gold headers (`header`), `dim`, `good`, `bad`. The map keeps its
own chart colours under `chart_*` (ink, paper). Fonts: **Pixelify Sans** for titles, headers and map labels; IM FELL
English for body text (a period serif reads better in long text, as Octopath's own body font does).

## 3. Making pixel art

- **HD pixel art:** draw at full resolution, one art pixel to one screen pixel at normal zoom, never upscaled.
  Detail comes from small colour ramps (3 to 5 tones), ordered dithering for gradients, and 1 px outlines.
- Window frames are 9-slice textures that **tile** rather than stretch, so their fill is an even dither that repeats
  cleanly; keep the centre a multiple of the dither period (2 px). Corners carry the filigree.
- Map ships (`assets/ships/<type>/`) are top-down, bow up: `hull`, `hull_damaged`, `sails_furled/half/full/torn`,
  all on the same canvas, with a soft drop shadow baked into the hull.
- Outline sprites with a near-black line; light comes from the upper left.
- Ships (side view, bow to the right): `assets/ships_side/<type>/hull.png`, `hull_damaged.png`, `sails.png`,
  `sails_torn.png`, and `layout.json` (`size`, `waterline` row, `flag` masthead, `masts`). Paint and sail colour
  tint the hull and sails, so draw them in light, neutral tones.
- Backdrop props (`assets/battle/`): islands, clouds and rocks; they stand on the water at their bottom edge.
- `tools/make_pixel_art.py` makes every placeholder. Replace any file with hand-made pixel art at the same path.

## 4. Light

- Time of day comes from the clock: bright noon, orange dusk with long shadows, blue night with lanterns.
- Every broadside is a flash of light (`OmniLight3D`) on the firing ship; fires flicker orange until they're put out.
- Glow is soft-light and only for bright things (flashes, fire, glints on the water). Fog thickens toward the horizon.
- The depth of field blurs both the far horizon and the near water, so the ships read as miniatures.
- A Break is the battle's big moment: the shields burst in shards, the world flashes white, time slows for a breath, and BREAK stands over her. Damage floats off the ship that took it (crits gold).
- Storms on the map are drawn by the cloud shader (`paper.gdshader`): dense dark cloud with pixel rain and lightning, a hurricane turning about its eye, fog as a white bank, a calm as a pale sheen.
