# HD2D RPG — Godot addons (installed 2026-11-08)

Target engine: **Godot 4.7.2-stable**, Forward+ renderer, GDScript.
All addons were downloaded from GitHub, extracted, and installed under `res://addons/<name>/` with a flat layout
(`addons/<name>/plugin.cfg` directly under `addons/`, no extra top folder). None of them are required to run the
prototype — the current `Main` scene works with its own `CameraRig` script — they are available to upgrade specific
parts of the project.

Download budget used: ~8 MB of addon zips (extracted ~17 MB) + 10.5 MB asset pack. Well under the 150 MB budget.

## Installed addons

| Name | Version | Source URL | License | Godot target | Installed path | Enable? | Risk notes |
|---|---|---|---|---|---|---|---|
| **Phantom Camera** | 0.11.0.4 | https://github.com/ramokz/phantom-camera/releases/tag/v0.11.0.4 | MIT | 4.4+ (README badge) | `res://addons/phantom_camera/` | **yes** (optional) | Ships GDScript **and** C# twins (`.cs`) — project is GDScript-only, so the C# files are simply unused; do not enable C# in the project later without checking for class-name clashes. 0.11.0.4 is built for 4.4+ (has explicit 4.3/4.4 version guards in `phantom_camera_host.gd`), 4.7 is untested upstream — smoke-test the follow camera after enabling. Editor plugin + runtime nodes, no project settings required. |
| **Aseprite Wizard** | 9.8.0 | https://github.com/viniciusgerevini/godot-aseprite-wizard/releases/tag/v9.8.0-4 | MIT | Godot 4 branch (4.x) | `res://addons/AsepriteWizard/` | **yes** (editor-only) | Purely an import/export helper; no runtime dependency, safe to remove later. Requires the **Aseprite CLI** to be configured once in `Editor Settings → Aseprite Wizard → Aseprite Command`; without it the plugin loads but .aseprite imports fail. No `.aseprite` files exist in the project yet — if the user doesn't own Aseprite (paid), this is unused; Libresprite's CLI can be pointed at instead. |
| **Dialogic** | 2.0-alpha-20 | https://github.com/dialogic-godot/dialogic/releases/tag/2.0-alpha-20 | MIT | **4.5+**; 4.6/4.7 recommended | `res://addons/dialogic/` | **yes** (enable when dialogue is added) | Alpha software: release notes state it fixes API breakage introduced by **Godot 4.7**, requires 4.5+, and that alpha upgrades can break old save states. On enable it registers the `Dialogic` autoload singleton and the `dialogic_default_action` input action automatically. 11 MB (includes example assets). |
| **GUT** (Godot Unit Test) | 9.7.1 | https://github.com/bitwes/Gut/releases/tag/v9.7.1 | MIT | **4.7.x** (`godot_4_7` branch per README) | `res://addons/gut/` | **optional** (dev/test only) | Exactly the release branch GUT publishes for Godot 4.7.x. Adds an editor bottom panel; disable before exporting a build. Not needed for the prototype. |

> Note: GitHub's `/releases/latest` endpoint returned GUT **9.6.1** (the 4.6.x build) as "latest". The README
> compatibility table shows **9.7.1** is the 4.7.x build, so 9.7.1 was installed deliberately.

## Enable list for `project.godot`

Current `hd2d-rpg/project.godot` has no `[editor_plugins]` section yet. Add this section (the Lead owns
`project.godot`; I did not edit it):

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/phantom_camera/plugin.cfg", "res://addons/AsepriteWizard/plugin.cfg", "res://addons/dialogic/plugin.cfg", "res://addons/gut/plugin.cfg")
```

Minimum useful set for the current prototype: `phantom_camera` + `AsepriteWizard`. Add `dialogic` when the
dialogue system is actually needed, and `gut` only for test runs. If enabling everything at once produces
editor errors, enable one at a time to isolate (Phantom Camera is the riskiest of the four on 4.7).

Required project settings: **none** for any of these. The Aseprite path is stored in `EditorSettings`
(user-level, not versioned), and Dialogic's autoload + input action are created by the plugin itself on first
enable.

## How each addon is wired into the HD2D prototype

### Phantom Camera 3D — replace/extend `scripts/camera_rig.gd`
The prototype already has a hand-written follow rig (`Main/CameraRig` → `Camera3D`, orthographic, damped lerp,
wheel zoom). Phantom Camera is a drop-in upgrade when you want priorities, tweens between shots, dead zones,
or velocity-based look-ahead:

1. Add a **`PhantomCameraHost`** node under `Main` (it owns the real `Camera3D` and picks the active
   `PhantomCamera3D` per `host_layers`).
2. Add a **`PhantomCamera3D`** node; its child must be the **`Camera3D`** carrying the HD2D framing
   (`projection = ORTHOGONAL`, `size ≈ 6–14`, `rotation.x ≈ -35°`, the same setup `CameraRig` uses today).
3. On the `PhantomCamera3D`:
   - `follow_mode = SIMPLE` (follows position with an offset, keeps the camera's fixed HD2D pitch),
   - `follow_target = res://scenes/player/player.tscn` instance (`Player`),
   - `follow_offset = Vector3(0, 0.6, 0)` and `follow_damping = true` to reproduce the current soft lerp,
   - `look_at_mode = NONE` (important — keeps the fixed isometric-ish angle),
   - `priority` above any other PCam (e.g. `10`) so the host selects it.
4. Then delete/disable the `CameraRig` script or its `Camera3D` so only one camera is current. Wheel-zoom can
   keep working by writing to the child `Camera3D.size`, or be replaced with `PhantomCameraTween` shots.

### Aseprite Wizard — pixel-art hero/enemy import
- One-time setup: `Editor Settings → Aseprite Wizard → Aseprite Command` → path to `Aseprite.exe` (e.g.
  `C:/Program Files/Aseprite/Aseprite.exe`). It is a user setting, not part of the repo.
- Import the hero sheet (`hero.aseprite`) either via the **Aseprite SpriteFrames** importer (creates a
  `SpriteFrames` resource usable by `AnimatedSprite3D`/`AnimatedSprite2D`), or open the **Spritesheet Wizard
  Dock** and push animations into the existing `AnimationPlayer`/`Sprite3D` setup.
- The project already forces nearest filtering (`rendering/textures/canvas_textures/default_texture_filter=0`),
  which is what pixel billboards need; keep texture filtering off on any 3D sprite material.
- Runtime cost: zero (plugin is editor-only). It can be removed at any time after import.

### Dialogic 2 — RPG dialogue
- Enabling the plugin adds the `Dialogic` autoload and the `dialogic_default_action` input action (Enter /
  Space / click / gamepad).
- Create a timeline in the **Dialogic** editor tab (e.g. `res://dialogic/timelines/intro.dtl`), add characters
  and a text box layout.
- Trigger from gameplay: `Dialogic.start("intro")` (returns an awaitable signal), and listen to
  `Dialogic.timeline_ended` to re-enable player movement. While a timeline is active, gate
  `Player._physics_process()` on `Dialogic.is_timeline_playing()` (or pause player input).
- The visual-novel style dialogue box is DOM/CSS independent (pure Godot UI), so it fits the HD2D look; keep it
  disabled until there is dialogue content to show.

### GUT — tests only
- Enable temporarily, write tests in `res://test/test_*.gd` extending `GutTest`, run from the GUT bottom panel
  or `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/*.gd`.
- Disable before exporting/committing a release build.

## Free CC0 asset pack

**Kenney Nature Kit 2.1** (CC0 1.0) — `res://assets/free/kenney_nature_kit/`

- 329 low-poly nature models as **GLB** (self-contained, no external textures) in `models/`:
  trees (`tree_default.glb`, `tree_oak.glb`, `tree_pineTallA.glb`…), grass (`grass.glb`, `grass_large.glb`,
  `ground_grass.glb`), rocks/cliffs, bushes, flowers, logs, bridges, tents, etc.
- License text kept verbatim in `License.txt`, credits/source in `CREDITS.md`, preview in `preview.png`.
- Suggestions for the grass field: scatter `tree_default.glb` / `tree_oak.glb` / `rock_*.glb` as
  `MeshInstance3D`, use `MultiMeshInstance3D` for `grass.glb` clumps, and add `StaticBody3D` +
  box/trimesh collisions only on trees/rocks the player can bump into.
- Source: https://kenney.nl/assets/nature-kit (pack version 2.1, creation date 2020-04-29).

## Verification performed (no engine run)

- `addons/<name>/plugin.cfg` exists for all 4; `[plugin] name/version/script` parsed; every referenced script
  file exists (`plugin.gd` / `gut_plugin.gd`).
- Layout flattened correctly: each plugin directory sits directly under `res://addons/` with `plugin.cfg` at
  its root (no nested `repo-name/` folder, no doubled `addons/addons/`).
- Godot 3 / removed-API scan over all `*.gd` in the addons:
  `yield(` = 0, `OS.get_unix_time` = 0, `TileMap.` = 0, `NavigationMesh.` = 0, Godot-3-style
  `export var` at line start = 0, `Directory.new()` = 0. The `instance_from_id(` hits are only in GUT and are
  valid Godot 4 API. No plugin source was modified.
- Godot target of each addon recorded from its own README/plugin.cfg/release notes (see table above).
- Sizes: phantom_camera 2.0 MB, AsepriteWizard 0.8 MB, dialogic 11 MB, gut 3.2 MB; Kenney pack 3.7 MB
  (329 GLB).
