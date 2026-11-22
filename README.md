# Silence of the limbs 

Multiplayer 3D game built in Godot 4 for Technozion / CSES.

The elevator pitch: 4 players spawn in an old church in the middle of a dense island. Everyone's body has been cut into four pieces (head, hands, torso, legs) and scattered across the zones. You run around, hunt down your opponents' body parts, haul them back to the center altar, and burn them. If all 4 of your parts get sacrificed, you're out. If the round timer expires, whoever deposited the most parts wins.

Along the way you find tarot cards scattered on the ground that let you screw with other players' controls, blind them, or blow them backward off a ledge.

---

## Core Systems & Implementation

### 1. Movement and Character Physics (`Player/Scripts/Player.gd`)

Default 3D character movement in Godot often feels like sliding on wet ice when you make sudden turns. Because this is a high-speed game about chasing people carrying your limbs, the controller was built with a few specific physics tweaks:

- **Turn acceleration snapping**: Instead of a flat `move_toward`, we track `ground_turn_acceleration = 40.0`. If your desired direction vector opposes your current velocity vector (`current_vel.dot(target_vel) < 0.0`), the controller kicks in higher acceleration so direction changes snap instantly instead of drifting.
- **Sliding**: Holding sprint and pressing crouch triggers a directional slide. It calculates an initial boost factor (`1.35 * slide_boost * (0.6 + 0.4 * (slide_timer / 0.65))`) that decays over a 0.65s timer, blending into crouch-walk if you stay down.
- **Takeoff speed preservation**: Air control is limited (`air_control = 0.3`), but your horizontal takeoff speed is captured at the moment of jumping (`air_speed = max(current_speed, air_speed)`) so you don't instantly lose sprint momentum in mid-air.
- **Input buffers and coyote time**: 0.15s jump buffer window and 0.10s coyote timer off ledges.
- **Ocean buoyancy**: Wading slows movement smoothly by submerge depth, and deep water floats the player at shoulder height (`WATER_FLOAT_CENTER_Y = 4.85`) with gentle wave bobbing so the camera stays above the surface.
- **Player shoving (`push_player`)**: You can walk up to an opponent and trigger an impulse knockback to physically knock them away from an altar deposit or a pickup, gated by a 1.5s client + server cooldown (`push_cooldown`) to prevent stunlock spam.
- **First-person camera feel**: Movement drives a speed-scaled sinusoidal headbob, smooth eye-height drop and roll tilt during crouch/slide, a velocity-scaled landing dip on touchdown, quadratic decaying trauma shake on shove/Tower knockback hits, and subtle rotational lag on the handheld flashlight.

### 2. Physical Body Parts (`BodyParts/bodypart.gd`)

Body parts are not just inventory numbers. They are actual `RigidBody3D` nodes with collision shapes and mass:
- When dropped or spawned, they react to terrain gravity and physics impulses.
- Players pick them up into an active hold slot attached to the camera's `HeadPosition` node with subtle walk/breathing carry sway and owner-aware hover/carry prompts (warning you if you hover your own limb).
- Depositing opponent parts grants passive stat bonuses based on part type: `LegsPart` permanently increases walk/sprint speed, `HeadPart` widens FOV, `HandsPart` scales `push_force` and `reach_distance`, and `TorsoPart` boosts `slide_boost` while dynamically expanding `tarot_capacity` (and adding extra HUD slots).
- Depositing an opponent's part at the central altar (`SpellCenter.gd`) registers the sacrifice on the authoritative host via RPC. When a player's 4th part is deposited, the host emits `player_eliminated`. On a 5-minute timeout, ties in deposits are broken by fewest parts lost before declaring a draw.

### 3. Tarot Cards & Status Effects (`Tarot/`)

Cards are structured as Godot custom resources (`TarotCard.gd` inheriting `Resource`), pairing a card definition with a `TarotEffect` script. Players start with 2 inventory slots (expandable via the `TorsoPart` buff), get hover/toast warnings when slots are full, and grounded pickups pulse with a subtle violet rim shimmer so they stay readable in dark woods.

- **Dark Moon**: Overrides the target's camera far plane and fog density, dropping view distance to near-blindness and narrowing FOV for 5 seconds.
- **Hanged Man**: Flips `input_multiplier = -1.0` on the victim client. All directional input is completely inverted for the duration.
- **Demon Speed**: Applies a raw speed multiplier (`speed_modifier = 2.0`) for 10 seconds.
- **The Tower**: Applies radial impulse knockback, launching nearby opponents away from you.
- **Recaller (Super Card)**: Teleports opponents back to their ritual stations.

#### The Blood Shrine Event
Mid-match, `GameManager.gd` halts normal flow, locks player camera/movement input, and broadcasts a voting prompt to all clients. If the majority votes to accept the deal:
- 20 seconds are permanently deducted from the match timer.
- Every player who voted yes gets the `Recaller` super card.

### 4. HUD, Compass & Lobby UX (`Maps/Scripts/MatchHUD.gd`, `CompassUI.gd`, `MainMenu/`)

- **Context-aware compass (`CompassUI.gd`)**: Smoothly interpolates (`lerp_angle`) toward the nearest opponent limb, tinted to that player's color. The moment you pick up a body part, the compass automatically flips to crimson and points straight back to the Church Altar (`SpellCenter`).
- **Tension feedback & spectator clarity**: Banners, tarot toasts, and tooltips fade smoothly with tweens; under 60 seconds, a procedural red edge vignette pulses alongside the heartbeat audio (with timer pulse under 15s); sacrificed players get a clear spectator overlay instead of freezing silently.
- **Lobby & Settings QoL**: Hosts see their local LAN IPv4 with a one-click **Copy IP** button, players can cycle characters with keyboard shortcuts and drag to spin the 3D preview, Direct IP persists across launches (`last_direct_ip`), the Pause Menu includes a compact Controls card, and Settings expose Master/SFX/Ambience sliders with live numeric readouts, Shadow Quality, SSAO/SSR/SDFGI toggles, deduplicated resolutions, and full gamepad focus navigation.
- **Playtest utilities**: `AudioManager.gd` automatically mutes unfocused windows for clean multi-instance testing on one PC, and pressing `F3` toggles a live FPS and ENet RTT ping overlay.

### 5. Networking & Replication (`Networking/NetworkManager.gd`)

Built using Godot's `ENetMultiplayerPeer` on port `8910`.

- **Authoritative host**: Match timers, player life states, body part spawn seeds, and sacrifice validations live strictly on the server/host instance.
- **LAN Auto-Discovery & Direct IP**: To avoid manually typing local IP addresses during playtesting, `NetworkManager.gd` spins up a lightweight UDP listener and broadcast loop on port `8911` using `PacketPeerUDP`. The host broadcasts a `FINDERS_KEEPERS_HOST` beacon; clients listen, parse sender IPs, and connect automatically. For networks where broadcast packets are blocked, players can enter a Direct IP on the Main Menu (saved across launches via `Settings.gd`) or copy the host's LAN IP directly from the Lobby.
- **Position & Rotation Interpolation**: Remote player movement is broadcast at 20Hz. Clients push received states into a sliding buffer (`network_position_buffer`, `network_timestamp_buffer`) and evaluate positions at `current_time - interpolation_time (0.12s)` using linear/spherical interpolation to keep remote puppets smooth without rubber-banding.
- **Deferred Background Scene Loading**: Rather than competing with Main Menu startup, `NetworkManager` defers `ResourceLoader.load_threaded_request` until entering the Lobby (`load_lobby()`), streaming the binary `Maps/GameMode.scn` (with automatic `.tscn` fallback) in the background while players pick characters.

### 6. Performance & Load-Time Optimization (`tools/optimize_gamemode_scene.gd`)

Large 3D Godot projects easily get bogged down by eager `preload()` chains, ASCII `.tscn` parsing, and un-merged foliage meshes. Startup and runtime performance were overhauled in three layers:

- **Fast cold boot (~30s → ~1s)**: `CharacterDefinition.gd` and `Player1..8.tres` load character FBX models lazily via `model_scene_path` instead of preloading all 8 characters (~368 MB imported / 68 4K textures) at startup. Legacy 3D `WorldObjects` and its SDFGI/SSIL/SSR/SSAO `WorldEnvironment` were stripped from `MainMenu.tscn`, and gameplay-only SFX in `AudioManager.gd` are deferred until match start.
- **Binary map pipeline (`Maps/GameMode.scn`)**: A reproducible headless Godot tool (`tools/optimize_gamemode_scene.gd` via `tools/optimize_gamemode_runner.tscn`) converts the 254.5 MB text `Maps/GameMode.tscn` into a ZSTD-compressed binary `Maps/GameMode.scn` (~122 MB, ~10× faster load):
  - Extracts 20 embedded raw `Image` sub-resources (~140.7 MB ASCII Base64) to `Maps/extracted_textures/` for VRAM-compressed `.s3tc.ctex` import.
  - Merges 6,471 individual foliage leaf meshes under `skull_area` into 11 indexed `ArrayMesh`es (-14,031 scene nodes total) and strips 604 empty `StaticBody3D` nodes.
  - Removes hidden `OceanTerrain3D` (81 unused ocean region files), redundant runtime `create_trimesh_shape()` calls on already-baked meshes, off-viewport stray geometry, and replaces the decorative 50k-tri angel statue concave collider with a fitted `BoxShape3D`.
- **Runtime GPU, animation & VRAM tuning**: `BoujieOcean` LODs and `far_edge` (`1800m`) were tuned to cut frame-1 `SurfaceTool` ocean generation by ~75–80%; `Sky3D` cumulus raymarching (`SkyMaterial.gdshader`) was reduced from 80 → 24 texture taps/pixel (~3.3× faster sky pass); `PlayerAnimationController.gd` caches remapped `AnimationLibrary` instances per `character_id`; and `.import` `process/size_limit` caps (1024px characters/props, 512px split body parts) plus removing `collision_baker.gd` from pickupable `SplitParts` GLBs slash VRAM without modifying source textures.

### 7. Automated Mesh Slicing Tool (`tools/split_character_parts.py`)

Rather than manually taking 8 character models into Blender, separating meshes, and exporting each limb by hand, we wrote a headless Blender Python script that automates the pipeline.

The script runs inside Blender CLI:
```bash
blender --background --python tools/split_character_parts.py
```
It reads each source FBX, matches Mixamo bone namespaces against defined vertex group hierarchies (`head`, `hands`, `torso`, `legs`), isolates the geometry, cleans unreferenced vertex groups and materials, normalizes origins, and exports clean static `.glb` files directly into `Models/characters/SplitParts/`.

---

## Controls

### Keyboard & Mouse
- **WASD**: Movement
- **Mouse**: Look
- **Shift**: Sprint
- **C / Ctrl (while sprinting)**: Slide
- **Space**: Jump
- **E**: Interact / Pick up body part / Pick up tarot card
- **Q**: Shove / Push player
- **1 / 2**: Use Tarot Card in Slot 1 / Slot 2
- **F**: Toggle flashlight
- **Esc**: Pause / Settings

### Controller (Gamepad)
- **Left Stick**: Movement
- **Right Stick**: Look
- **Left Stick Click / Bumper**: Sprint
- **Right Trigger / B Button (while sprinting)**: Slide
- **A Button**: Jump
- **X Button**: Interact / Pick up
- **B Button**: Shove / Push
- **D-Pad Left / Right**: Use Tarot Slot 1 / Slot 2
- **D-Pad Up**: Toggle flashlight
- **Start**: Pause

---

## Project Structure

```
FindersKeepers-CSES/
├── Audio/                  # Positional audio, footstep controller, ambient loops
├── BodyParts/              # Collectible RigidBody3D parts & SpellCenter altar logic
│   ├── bodypart.gd         # Base class for collectible physics limbs
│   └── SpellCenter.tscn    # Altar area with sacrifice triggers
├── MainMenu/               # Lobby UI, host/join menus, character selection
├── Maps/                   # Game scenes, Terrain3D assets, forest layouts
│   ├── Scripts/            # MatchHUD, CompassUI, RenderScaler, collision bakers
│   └── GameMode.tscn       # Main map scene
├── Models/                 # Character FBXs, split limb GLBs, materials
├── Networking/             # NetworkManager (ENet peer management & UDP LAN discovery)
├── Player/                 # First-person player controller and animation states
│   └── Scripts/Player.gd   # Movement, slide math, tarot trigger inputs
├── scripts/managers/       # GameManager (match state machine, timer, win checks)
├── Tarot/                  # Tarot card definitions (.tres) and effect scripts
└── tools/                  # Headless Blender scripts for automated FBX bisecting
```

---

## Running the Project

### Requirements
- **Godot 4.3+ (Forward+ renderer)**
- **Git LFS** (needed to pull the 3D meshes and terrain textures)

### Setup
```bash
git clone https://github.com/vvadithya/FindersKeepers-CSES.git
cd FindersKeepers-CSES
git lfs pull
```

Open Godot, import `project.godot`, and let the assets import on first launch.

### Testing Multiplayer on a Single Machine
1. In the Godot editor, go to **Debug > Run Multiple Instances** and select **2** or **4** instances.
2. Press **F5** to run.
3. On instance 1, click **Host**.
4. On instance 2+, the host will appear in the lobby list via UDP discovery. Click **Join**.
5. Select characters and hit **Start Game**.

---

## Contributors

Built for CSES / Technozion by:
- Vedula Venkata Adithya ([@vvadithya](https://github.com/vvadithya) / [repository](https://github.com/vvadithya/FindersKeepers-CSES))
- Ishaan Pandey ([@TheSophisticated](https://github.com/TheSophisticated) / [upstream repository](https://github.com/TheSophisticated/FindersKeepers-CSES))
- Soham Siddhartha Roy ([@CleverFox29](https://github.com/CleverFox29) / [repository](https://github.com/CleverFox29/FindersKeepers-CSES))
- Ram Siddhartha Mamillapalli ([@RamSiddhartha](https://github.com/RamSiddhartha))
- Tanmay Saraf ([@tanmaysaraf07](https://github.com/tanmaysaraf07) / [repository](https://github.com/Tanmay-Saraf/FindersKeepers-CSES))
- Kamran Bilal Bhat ([@kamranbb-29](https://github.com/kamranbb-29))
- Samyak Jain ([@SamyakJain092006](https://github.com/SamyakJain092006) / [repository](https://github.com/SamyakJain092006/FindersKeepers-CSES))
