# About Silence of the Limbs

**Silence of the Limbs** (repo: `FindersKeepers-CSES`) is a 2–4 player 3D first-person multiplayer horror scavenger game built in **Godot 4.7 (Forward+)** for **CSES / Technozion**.

---

## Premise & Core Loop

Four players wake up inside a decaying church at the center of an overgrown island. Everyone's body has been dismembered into four physical pieces — **Head**, **Hands**, **Torso**, and **Legs** — and scattered across the graveyard, ruins, swamp, and skull forest.

1. **Hunt**: Track down opponents' limbs using your color-coded compass while keeping track of where your own parts are vulnerable.
2. **Haul**: Pick up an opponent's physical limb (`RigidBody3D`) and sprint/slide back toward the church while your compass redirects to the central altar (`SpellCenter`).
3. **Sabotage**: Grab glowing Tarot cards scattered across the island (`Dark Moon`, `Hanged Man`, `Demon Speed`, `The Tower`, `Recaller`) or shove rivals (`[Q]`) to knock carried limbs loose right before a deposit.
4. **Sacrifice**: Burn opponent limbs at the altar to stack permanent passive buffs (speed, FOV, shove force/reach, slide boost, extra Tarot slots). Lose all 4 of your parts and you are eliminated; survive until the 5-minute clock runs out and the top depositor wins.

Mid-match, the **Blood Shrine** interrupts the round with a group vote: sacrifice 20 seconds off the global timer in exchange for the `Recaller` super card.

---

## Playable Cast

Eight custom Mixamo-rigged characters selectable in the pre-match 3D Lobby (with unique split limb `.glb` meshes generated via Blender CLI):

| Slot | Character | Model |
|---|---|---|
| Player 1 | Kamran | `Ch21_nonPBR.fbx` |
| Player 2 | Tanmay | `Ch02_nonPBR.fbx` |
| Player 3 | Soham | `Ch23_nonPBR.fbx` |
| Player 4 | Adithya | `Ch37_nonPBR.fbx` |
| Player 5 | Ram | `Ch33_nonPBR.fbx` |
| Player 6 | Donyak Bhatia | `Ch22_nonPBR.fbx` |
| Player 7 | Ishaan | `Ch31_nonPBR.fbx` |
| Player 8 | Samyak | `Remy.fbx` |

---

## Tech Stack

- **Engine**: Godot 4.7 (Forward+ Vulkan renderer)
- **Networking**: Authoritative host over `ENetMultiplayerPeer` (UDP port `8910`) with automatic LAN discovery (`PacketPeerUDP` port `8911`) and persistent Direct IP fallback
- **World & Environment**: `Terrain3D`, `Sky3D`, `BoujieOcean` Gerstner wave water, custom horror typography & screen-blur transitions
- **Asset Tooling**: Headless Blender Python limb-slicing pipeline (`tools/split_character_parts.py`) and headless Godot binary map optimizer (`tools/optimize_gamemode_scene.gd`)

---

## Latest Release — `v2.0.0`

**Highlights in `v2.0.0`**:
- **GTA V-Style Rotating Minimap Radar**: Bottom-left tactical radar backed by a pre-baked 512×512 top-down island map (`tools/bake_minimap.gd` → `Maps/Textures/minimap_island.png`) showing real `Terrain3D` contours, ocean coastline, Church Altar cross, forest, ruins, graveyard, skull area, rotating North badge, player FOV cone, `[M]` expanded zoom toggle, and color-coded circular dots for other living players (with zero extra 3D camera overhead).
- **Keyboard-Only Custom Player Names**: Players on keyboard/mouse can set a custom display name in the Lobby (persisted in `Settings` and synced over `NetworkManager` to Lobby, HUD legend, banners, prompts, 3D owner tags, and Game Over), while controller players remain locked to default player labels.
- **Skin Tone & Hair Customization**: Live 3D Lobby preview and networked avatar + severed limb customization across 4 preset skin tones (`Black`, `Caucasian`, `Indian`, `Chinese` + `Default`) and 7 hair presets (`Jet Black`, `Dark Brown`, `Blonde`, `Auburn`, `Silver`, `Crimson`, `Shaved` + `Default`) using a cached lightweight shader that leaves clothing untouched.
- **Multiplayer White Arrow Compass Hardening**: Restored crisp white arrow body-part guidance (with subtle owner-color base pip and crimson Altar redirect), replicated `is_carried`/`is_collected` states, added `"body_parts"`/`"GameMode"` group discovery, and fixed premature 10m fade-out.
- **Plain-Text Match Export with Native Save Dialog**: Export full match summaries, player loadouts/standings, and timestamped event timelines to `.txt` via a native Save File Dialog from either the Game Over screen or Pause Menu.

---

## Previous Release — `v1.0.0`

**Highlights in `v1.0.0`**:
- **Complete 2–4 player LAN & Direct IP multiplayer loop**: Pre-match 3D character lobby with LAN IP copy button, authoritative sacrifice tracking, 5-minute match timer with tie-breaking, Blood Shrine voting event, and eliminated spectator overlay.
- **Tuned first-person movement & horror feel**: Turn-snapping movement, sprint-sliding with eye-height drop and roll tilt, speed-scaled headbob, landing dip, knockback camera shake, ocean buoyancy, handheld flashlight lag, and 1.5s server-enforced shove cooldown.
- **Body part buffs & Tarot cards**: Wired passive buffs for all 4 limb types (including dynamic 3–4 Tarot slot HUD expansion from `TorsoPart`), owner-color compass that redirects to the Church Altar while carrying a limb, pulsing tarot pickups, and smooth HUD fade/panic-vignette effects.
- **Major startup & runtime optimization**: Lazy character/audio loading and stripped 3D menu cut launch time from ~30s down to ~1s; binary `Maps/GameMode.scn` removes 14,031 nodes, merges 6,471 foliage leaf meshes into 11, and extracts 140.7 MB of inline textures (~10× faster match load); `BoujieOcean`, `Sky3D`, animation caching, and 4K `.import` caps improve FPS and VRAM.
- **Playtest & Accessibility QoL**: Live numeric Settings sliders, SSAO/SSR/SDFGI toggles, full gamepad focus navigation, Pause Menu controls card, automatic unfocused-window audio mute, and `F3` FPS/ENet ping overlay.

---

## Team

Built for **CSES / Technozion** by:
- Vedula Venkata Adithya ([@vvadithya](https://github.com/vvadithya))
- Ishaan Pandey ([@TheSophisticated](https://github.com/TheSophisticated))
- Soham Siddhartha Roy ([@CleverFox29](https://github.com/CleverFox29))
- Ram Siddhartha Mamillapalli ([@RamSiddhartha](https://github.com/RamSiddhartha))
- Tanmay Saraf ([@tanmaysaraf07](https://github.com/tanmaysaraf07))
- Kamran Bilal Bhat ([@kamranbb-29](https://github.com/kamranbb-29))
- Samyak Jain ([@SamyakJain092006](https://github.com/SamyakJain092006))
