# SEGMENTS — runtime-built narrative segments

`scenes/segment/segment.tscn` is a bare `Node3D` named **Segment** with
`scenes/segment/segment.gd` attached. **Nothing is built in `_ready()`**: the
game manager creates the node, calls `setup(config)`, then reads the spawn
points back out. One segment is one small, deterministic slice of the 11-segment
walk — ground, dirt path, grass, props, atmosphere and the exit landmark.

Files:

| File | Purpose |
| --- | --- |
| `scenes/segment/segment.tscn` | minimal scene: one Node3D + segment.gd |
| `scenes/segment/segment.gd` | the whole builder + tuning constants |
| `docs/SEGMENTS.md` | this guide |

No new shaders were needed: the grass reuses the verified
`res://shaders/world/grass.gdshader`.

Optional art (loaded only when `ResourceLoader.exists()` is true):

- `assets/generated/grass_ground.png` — ground albedo (`TEXTURE_FILTER_NEAREST`)
- `assets/generated/path_dirt.png` — path ribbon albedo (fallback: warm brown)
- `assets/generated/grass_blade.png` — grass alpha cutout
- `assets/generated/flower_white.png`, `flower_yellow.png` — pixel flowers
- `assets/free/kenney_nature_kit/models/*.glb` — CC0 trees / rocks / bushes

Every one of them falls back gracefully; the segment still builds and runs.

---

## Game-manager contract

```gdscript
var segment := preload("res://scenes/segment/segment.tscn").instantiate()
add_child(segment)
segment.setup(SegmentPresets.SEGMENTS[index])

player.global_position = segment.get_player_start()   # y == 0

if config["npc_id"] != "":
    npc.global_position = segment.get_npc_position()  # y == 0

segment.exit_reached.connect(_on_exit)                # emitted exactly once
```

Public API:

| Member | Meaning |
| --- | --- |
| `signal exit_reached` | emitted **once** when a body in group `"player"` enters the `ExitArea` sphere |
| `setup(config: Dictionary)` | builds everything; call once, after `add_child()` |
| `get_player_start() -> Vector3` | spawn point, y = 0 |
| `get_npc_position() -> Vector3` | `config.npc_position`, y = 0 |

`setup()` is idempotent: a second call logs a warning and is ignored.
`config` is merged over `DEFAULT_CONFIG` (a copy of `SegmentPresets.SEGMENTS[0]`),
so any missing key uses the first-preset value. `title` and `scenery_only` are
manager-only keys; the builder ignores them.

---

## Config schema

| Key | Type | Used for |
| --- | --- | --- |
| `id` | String | RNG seed — the same id always builds the same world |
| `area_size` | float | ground plane + playable square (m), 120 |
| `sky_top`, `sky_horizon`, `sky_ground_bottom`, `sky_ground_horizon` | Color | `ProceduralSkyMaterial` |
| `sun_color`, `sun_energy`, `sun_rotation_deg` | Color/float/Vector3 | `DirectionalLight3D` |
| `ambient_color`, `ambient_energy` | Color/float | `AMBIENT_SOURCE_COLOR` ambient |
| `fill_energy` | float | cool sky-bounce `DirectionalLight3D` (0 = off) |
| `fog_color`, `fog_density`, `fog_sun_scatter` | Color/float | environment fog |
| `tonemap_exposure`, `saturation`, `contrast` | float | FILMIC tonemap + colour grade |
| `glow_intensity`, `glow_threshold` | float | glow |
| `ground_tint` | Color | ground albedo colour |
| `ground_uv_tiles` | float | ground UV repeats (fallback `area_size / 12.8`) |
| `grass_grid` | float | blade grid spacing (auto-widened to respect the budget) |
| `grass_width`, `grass_height` | float | `QuadMesh` blade size |
| `grass_base`, `grass_tip`, `grass_dry` | Color | grass shader colours |
| `grass_dry_mix`, `wind_strength`, `wind_speed` | float | grass shader |
| `path_points` | Array[Vector2] | path control polygon in world XZ |
| `path_width` | float | path ribbon width |
| `prop_tree_models` | Array[String] | Kenney GLB file names (from `KIT_DIR`) |
| `prop_tree_count`, `prop_rock_count`, `prop_bush_count`, `prop_flower_count` | int | scatter counts |
| `prop_tint` | Color | multiplied onto the Kenney palette |
| `tree_scale` | float | tree height scale |
| `player_start`, `npc_position`, `exit_position` | Vector2 | world XZ anchors |
| `npc_id` | String | non-empty means "segment has an NPC" (grass clearing around it) |

---

## Builder flow (`segment.gd`)

`setup()` seeds the RNG from `id.hash()`, resolves the config, then calls, in
order:

1. `_sample_path()` — Catmull-Rom samples of `path_points`, ~0.5 m apart.
2. `_build_path_near_mask()` — a 1 m coarse mask that is a strict superset of
   the near-path region. Distance-to-polyline is only evaluated inside it
   (fast reject), then an exact point-segment distance decides.
3. `_build_environment()` — procedural sky, sun with 4-split shadows, cool fill,
   fog, FILMIC tonemap, glow, saturation/contrast, far DOF via
   `CameraAttributesPractical`.
4. `_build_ground()` — textured `PlaneMesh` at y = 0, a visual-only 2.4× backdrop
   skirt at y = −0.04, the `BoxShape3D` floor (`layer 1`, `mask 0`, y = −1) and
   four invisible 6 m perimeter walls.
5. `_build_path_mesh()` — ribbon `ArrayMesh` at y = 0.02 from the samples;
   UVs `u = 0..width/2.5` across, `v = distance/2.5` along; all normals +Y;
   each quad carries both windings so the ribbon can never be culled.
6. `_build_grass()` — one `MultiMeshInstance3D`: jittered `grass_grid` grid over
   the whole area, skipped near the path (`path_width * 0.5 + 0.15`), around
   `player_start` (r 2.5) and around `npc_position` (r 2.5, only when
   `npc_id != ""`), modulated by the large-scale density patches. Blade
   transforms go in as a `PackedVector3Array` + `PackedColorArray` custom data
   (the `_floats_to_vec3_transforms` packing from `world.gd`); one draw call,
   no shadow casting. Budget cap **95 000** blades — if `area_size / grass_grid`
   would exceed it the effective grid is widened and a warning is printed.
7. `_build_props()` — trees (`prop_tree_models` + `prop_tree_count`), rocks,
   bushes, flowers. Trees/rocks/bushes mix a path-corridor band with uniform
   scatter, keeping clear of the path (`path_width + 1.0`), `player_start`
   (r 4), `npc_position` (r 3), `exit_position` (r 3.5) and each other. A ring of
   larger framing trees along the inside of the perimeter walls hides the world
   edge (no colliders, like `world.gd`'s ring). Scattered trees get cylinder
   colliders, big rocks sphere colliders. GLB loading, per-surface tinting and
   the teal→green / metallic-fix material logic are copied verbatim from the
   verified `scenes/world/world.gd`.
8. `_build_exit()` — `Area3D` + `SphereShape3D` r 2.5 at `exit_position`,
   `collision_mask = 2` (Player layer), fires `exit_reached` once for a body in
   group `"player"`. The landmark is two stone pillars flanking the path with
   glowing caps, a ring of 8 emissive stones and a warm `OmniLight3D`.

Everything is static: there are no per-frame scripts. Wind is shader-side.

---

## Tuning constants (`segment.gd`, top of file)

- **Ground**: `GROUND_UV_TILE_SIZE` (12.8 m per texture tile),
  `BACKDROP_FACTOR` (2.4), `WALL_HEIGHT` (6), `WALL_THICKNESS` (2).
- **Path**: `PATH_STEP` (0.5 m sampling), `PATH_Y` (0.02), `PATH_UV_TILE`
  (2.5 m per texture repeat), `PATH_FALLBACK_COLOR`.
- **Grass**: `MAX_BLADES` (95 000), `GRASS_JITTER` (0.48 of the grid),
  `GRASS_*_SCALE_MIN/MAX` (blade jitter), `DENSITY_*` (patch mask),
  `CLEAR_PLAYER` / `CLEAR_NPC` (2.5), `PATH_CLEAR_MARGIN` (0.15),
  `WIND_DIRECTION`.
- **Prop scatter**: `PATH_PROP_CLEAR`, `PROP_AVOID_PLAYER/NPC/EXIT`,
  `TREE_SPACING` / `ROCK_SPACING` / `BUSH_SPACING`, `*_CORRIDOR_RATIO`,
  `CORRIDOR_INNER/OUTER`, `EDGE_INSET` / `EDGE_FRAME_SPACING`.
- **Atmosphere**: `SKY_*`, `SUN_SHADOW_DISTANCE`, `FILL_*`,
  `FOG_AERIAL_PERSPECTIVE`, `DOF_*`.
- **Exit**: `EXIT_RADIUS`, `EXIT_RING_RADIUS`, `EXIT_RING_STONES`,
  `EXIT_GLOW_COLOR`, `EXIT_GLOW_ENERGY`.

## Expected counts (default config, id `s1_morning`)

- grass grid 0.45 m over 120 m → ~267 × 267 cells. Expected blades per preset
  (density mask + skips simulated): **44 k–56 k**, e.g. 49 k for `s1_morning` —
  one MultiMesh, no shadows, well inside the 95 k budget
- path samples ~165–175, one ribbon mesh (~1.4 k triangles)
- trees: `prop_tree_count` scattered + ~64 perimeter framing trees;
  rocks / bushes / flowers from their config counts
- ~1 `WorldEnvironment` + 2 `DirectionalLight3D` + 1 `OmniLight3D`,
  ~10–20 `MultiMeshInstance3D`, one `StaticBody3D` per scattered tree / big rock
  plus 5 wall/floor bodies

---

## 2026 扩展：11 段

`scripts/game/segment_presets.gd` 现在有 11 组参数，按顺序：

1. `s1_morning` 一 · 晨光（纯风景）
2. `s2_noon` 二 · 正午（红 阿燃）
3. `s3_forest` 三 · 林间（黄 阿衡）
4. `s4_creek` 四 · 溪畔（纯风景）
5. `s5_flowerfield` 五 · 花野（绿 阿禾）
6. `s6_mountainpath` 六 · 山道（蓝 阿砚）
7. `s7_highland` 七 · 高地（紫 阿遥）
8. `s9_woodmill` 八 · 木场（橙 阿作）
9. `s10_windhill` 九 · 风坡（粉 阿游）
10. `s11_oldsteps` 十 · 旧阶（青 阿序）
11. `s8_summit` 十一 · 山顶（纯风景 → 结局）

新增三段是在原有 `s6_mountainpath` / `s5_flowerfield` / `s7_highland` 的参数基础上
复制后改写天色、雾、地面色调、树/花/木料/石阶密度与 NPC 位置。新增段落的独白在
`Narrative.MONOLOGUES` 的 `s9_woodmill` / `s10_windhill` / `s11_oldsteps`。
