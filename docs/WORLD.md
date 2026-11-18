# WORLD — HD2D grass field

`scenes/world/world.tscn` is a bare `Node3D` named **World** with
`scenes/world/world.gd` attached. **Everything else is created in
`_ready()`** — ground, grass, props, sky, sun, fog. There are no per-frame
scripts: wind is entirely shader-side and every prop is a static MultiMesh.

Files written by the world builder:

| File | Purpose |
| --- | --- |
| `scenes/world/world.tscn` | minimal scene: one Node3D + world.gd |
| `scenes/world/world.gd` | builds the whole world from the constants block |
| `shaders/world/grass.gdshader` | grass blade wind / colour / alpha cutout |
| `docs/WORLD.md` | this tuning guide |

Optional art (loaded only when `ResourceLoader.exists()` is true):

- `assets/generated/grass_ground.png` — ground albedo, tiled `uv1_scale = 24`
- `assets/generated/grass_blade.png` — alpha cutout for the blades
- `assets/generated/flower_white.png`, `flower_yellow.png` — pixel flowers
- `assets/free/kenney_nature_kit/models/*.glb` — CC0 low-poly trees / rocks / bushes

If any of these are missing the world falls back (flat green ground, untextured
blade quads, primitive trees) and still runs.

---

## What's in the scene

| Node | Kind | Notes |
| --- | --- | --- |
| `WorldEnvironment` | WorldEnvironment | procedural sky, sky ambient, FILMIC tonemap, glow, warm fog |
| `Sun` | DirectionalLight3D | `(-52, -35, 0)`, energy 1.55, 4-split shadows, 80 m shadow distance |
| `FillLight` | DirectionalLight3D | cool 0.22 sky-bounce fill, no shadows |
| `Ground` | MeshInstance3D | `PlaneMesh` 90 × 90, top at **y = 0** |
| `GroundBackdrop` | MeshInstance3D | 260 × 260 visual skirt at y = −0.04 (no collision) |
| `GroundBody` | StaticBody3D | layer 1, mask 0, `BoxShape3D` 90 × 2 × 90 at y = −1 |
| `ClearingTint` | MeshInstance3D | soft radial dirt tint at the spawn clearing |
| `Grass` | MultiMeshInstance3D | ~30.4k blade quads, custom data, **no shadow casting** |
| `ClearingTufts` | MultiMeshInstance3D | short clumps inside the 7 m clearing |
| `Tree_0…4` | MultiMeshInstance3D | ~94 Kenney GLB trees (5 variants, 1 MM per mesh part) |
| `Rock_0…2` | MultiMeshInstance3D | 14 Kenney rocks |
| `Bush_0…1` | MultiMeshInstance3D | 12 Kenney bushes |
| `FlowersWhite/Yellow` | MultiMeshInstance3D | 28 pixel-art flower quads |
| tree/rock bodies | StaticBody3D | cylinder / sphere colliders on the bigger props |

Expected instance counts (seeded RNG, so they are always the same):

- grass blades: **~30,360** (176 × 176 cells of 0.5 m over ±44 m, minus the
  7 m spawn clearing) — inside the required 25k–35k band
- clearing tufts: 80 clumps × 9 = **720**
- trees: **94** (4 hand-placed framing + 22 scattered + 68 in the 32–42 m ring)
- rocks: 14, bushes: 12, flowers: 28
- draw objects: ~20 MultiMeshes + 2 ground planes + ~40 prop colliders
  (well under the ~2.5k budget)

---

## Tuning constants (`scenes/world/world.gd`, top of file)

### Ground

| Constant | Default | Effect |
| --- | --- | --- |
| `GROUND_SIZE` | `90.0` | playable floor size in metres |
| `GROUND_UV_TILES` | `24.0` | texture repeats across the floor |
| `GROUND_FALLBACK_COLOR` | `(0.30, 0.43, 0.21)` | colour used when the PNG is missing |
| `BACKDROP_SIZE` / `BACKDROP_DROP` | `260` / `0.04` | visual-only skirt hiding the world edge |

### Spawn clearing

| Constant | Default | Effect |
| --- | --- | --- |
| `CLEARING_RADIUS` | `7.0` | no dense grass inside this radius |
| `CLEARING_TINT_ENABLED` | `true` | soft dirt tint under the player |
| `CLEARING_TINT_RADIUS` / `_ALPHA` | `10.5` / `0.34` | size / strength of that tint |
| `CLEARING_TUFT_CLUMPS` × `_BLADES` | `80 × 9` | short "trampled" grass clumps in the clearing |
| `CLEARING_TUFT_HEIGHT` | `0.30` | tuft height in metres |

### Grass

| Constant | Default | Effect |
| --- | --- | --- |
| `GRASS_GRID` | `0.5` | jittered grid spacing (smaller = denser + slower startup) |
| `GRASS_EXTENT` | `44.0` | blades cover ±44 m (ground is ±45) |
| `BLADE_WIDTH` / `BLADE_HEIGHT` | `0.10` / `0.42` | quad size in metres (≈ 4 × 17 px on screen) |
| `BLADE_HEIGHT_MIN/MAX` | `0.70` / `1.25` | per-blade height scale jitter |
| `BLADE_WIDTH_MIN/MAX` | `0.80` / `1.20` | per-blade width scale jitter |

### Wind (passed to the shader, shader defaults match)

| Constant | Default | Effect |
| --- | --- | --- |
| `WIND_STRENGTH` | `0.085` | max tip deflection in metres (0.05–0.12 recommended) |
| `WIND_SPEED` | `1.70` | sway frequency |
| `WIND_DIRECTION` | `(0.86, 0.50)` | world-space wind direction (normalised in shader) |

Colour gradient, dry-tint mix and the alpha threshold live in
`shaders/world/grass.gdshader` (`base_color`, `tip_color`, `dry_color`,
`dry_mix`, `alpha_threshold`, `blade_height`).

### Props

| Constant | Default | Effect |
| --- | --- | --- |
| `SEED` | `20261108` | fixed seed → identical world every run |
| `TREE_SCATTER_COUNT` | `22` | scattered trees (annulus 9.5–30 m) |
| `TREE_RING_COUNT` | `68` | dense ring at 32–42 m |
| `ROCK_COUNT` | `14` | rocks (9–34 m) |
| `BUSH_COUNT` | `12` | bushes (7.2–26 m) |
| `FLOWER_COUNT` / `FLOWER_CLEARING_COUNT` | `18` / `10` | flower quads |
| `PROP_TINT` | `(1.00, 1.06, 0.80)` | colour grade multiplied onto the imported Kenney palette (teal leaves → greener, fall leaves → warmer gold). `Color(1,1,1,1)` disables it |
| `TREE_MODELS` / `ROCK_MODELS` / `BUSH_MODELS` | see file | which `.glb` files to use; swap in `tree_*_fall`, `tree_pine*`, `rock_large*`, etc. |

The four hand-placed framing trees sit just outside the clearing at roughly
(−7.9, 2.2), (7.7, 3.6), (−6.9, −1.6) and (7.0, −1.2) so the opening shot has
trees and long shadows around the hero. They are inside `_build_tree_field()`.

### Lighting / atmosphere

| Constant | Default | Effect |
| --- | --- | --- |
| `SUN_COLOR` | `#FFE3B3` | warm sunlight |
| `SUN_ENERGY` | `1.55` | sun brightness |
| `SUN_ROTATION_DEG` | `(-52, -35, 0)` | low warm sun → long shadows |
| `SUN_SHADOW_DISTANCE` | `80.0` | directional shadow range (4 splits) |
| `FILL_LIGHT_ENABLED` | `true` | cool fill light on the shadow side |
| `AMBIENT_ENERGY` | `0.65` | sky ambient strength |
| `FOG_DENSITY` / `FOG_COLOR` | `0.014` / warm grey | aerial haze |
| `SKY_*_COLOR` | blue / pale horizon / olive ground | procedural sky palette |

---

## Framing note (important for art direction)

The camera is **orthographic, size 9, pitch −36.4°**. Orthographic projection
means the view volume is a slab, not a cone: from the default zoom the camera
sees a patch of ground roughly **16 m wide × 15 m deep** around the player
(x ±8, z −7.5…+7.8 relative to the player), and the sky/horizon is *not* in
frame at all. Anything standing on the ground further than that is clipped by
the top of the screen, not faded by distance.

Consequences:

- the dense 32–42 m `TREE_RING` is **not visible at size 9** — it is horizon
  insurance for a zoomed-out camera (size ≳ 22) or a shallower pitch. It is
  cheap (one MultiMesh per tree variant), so it stays in;
- the hand-placed framing trees at radius ≈ 8 m are what actually frames the
  opening shot;
- fog is a subtle warm veil over the near field, not a distance cue yet.

If the ring should be visible in the default shot, the camera (not this scene)
needs `size ≈ 22–26`, or a perspective camera.

---

## Things to know / gotchas

- **Blade texture orientation** is resolved geometrically: the shader derives a
  `tip` factor from `VERTEX.y` (not from mesh UVs) and samples the blade texture
  with `vec2(UV.x, 1.0 - tip)`, so the art's top row lands at the blade tip
  regardless of `PlaneMesh` UV conventions. If the cutout ever looks upside
  down, flip that one line in `grass.gdshader`.
- **Blades do not cast shadows** (`cast_shadow = OFF` on the grass MultiMesh);
  the ground, trees, rocks, bushes and flowers do.
- **GLB scale is normalised at runtime** from each model's AABB, so the Kenney
  models do not depend on their authoring units; trees are rescaled to
  `height` metres and their lowest point is placed on y = 0.
- **Grass `transform_array`** is written as 12 floats per blade
  (basis columns + origin). Blades only use yaw + diagonal scale, so the world
  looks identical whichever column/row convention a given Godot build uses.
- **Prop colliders**: tree trunks get a `CylinderShape3D`, bigger rocks a
  `SphereShape3D`; bushes/flowers/ring trees have no collider. The player can
  walk anywhere in ±45 m without leaving the floor.
- **Startup cost**: ~30k blades are generated in GDScript once (~0.1 s), then
  never touched again. No per-frame allocation.

## If something looks wrong, try this first

| Symptom | Knob |
| --- | --- |
| grass too sparse / too dense | `GRASS_GRID` (0.4 denser, 0.6 sparser) |
| blades too tall / short | `BLADE_HEIGHT`, `BLADE_HEIGHT_MIN/MAX` |
| sway too strong / calm | `WIND_STRENGTH`, `WIND_SPEED` |
| too much / little haze | `FOG_DENSITY` |
| trees look cold/teal | `PROP_TINT` towards `(1.0, 1.10, 0.72)` |
| clearing too bare | raise `CLEARING_TUFT_CLUMPS`, lower `CLEARING_RADIUS` |
| shadows too hard | `Sun.shadow_blur`, `light_angular_distance` in `_build_environment()` |

---

## 最终调参（Lead 验收，覆盖上表数值）

第一版实现跑通后做了视觉调优，以下为**当前实际生效**的关键值（以 `scenes/world/world.gd` 顶部常量为准）：

| 项目 | 初版 | 最终 | 原因 |
| --- | --- | --- | --- |
| `GROUND_UV_TILES` | 24 | **7** | 512px 贴图按 12.8 m/tile 平铺，1 texel ≈ 1 屏幕像素，地面细节才看得清 |
| 地面 `albedo_color` | 1,1,1 | **(0.74, 0.84, 0.70)** | 压暗地面，避免整屏发白 |
| `CLEARING_RADIUS` | 7.0 | **3.5** | 7 m 空地占满画面，改为小片踩踏区 |
| `CLEARING_TINT_RADIUS/_ALPHA` | 10.5 / 0.34 | **5.0 / 0.30** | 同上 |
| `CLEARING_TUFT_CLUMPS × _BLADES` | 80×9 | **40×10** | 中央不再是一大团深色草 |
| `GRASS_GRID` | 0.5 | **0.4** | 配合更宽的草叶，单根草读作“像素草丛” |
| `BLADE_WIDTH / BLADE_HEIGHT` | 0.10 / 0.42 | **0.30 / 0.46** | 关键改动：让 16×32 草叶贴图有足够像素，像 HD2D 像素草丛而不是细刺 |
| `BLADE_HEIGHT_MIN/MAX`、`WIDTH_MIN/MAX` | 0.70/1.25、0.80/1.20 | **0.62/1.35、0.72/1.28** | 更自然的随机高矮 |
| 草地密度补丁 | 无 | 按 `sin(px*0.13)*sin(pz*0.11)` 跳过部分格子 | 避免均匀地毯感；实测草叶数 ~34.6k |
| `SUN_ROTATION_DEG` | (-52, -35, 0) | **(-40, -33, 0)** | 更低的太阳 → 更长更戏剧化的影子 |
| `SUN_ENERGY` | 1.55 | **1.35** | 降低过曝 |
| 环境光 | 天空取色 0.65 | **AMBIENT_SOURCE_COLOR (0.72,0.80,0.66) × 0.30** | 去掉天空蓝造成的青色调 |
| `FILL_LIGHT energy` | 0.22 | **0.10** | 同上 |
| `FOG_DENSITY` / `FOG_COLOR` | 0.014 / (0.82,0.83,0.75) | **0.004 / (0.72,0.78,0.68)** | 初版雾太重、整屏发灰 |
| 色调映射 | FILMIC | **FILMIC + exposure 0.92 + saturation 1.18 + contrast 1.08** | 提升饱和度/对比，HD2D 更“鲜” |
| 景深 | 无 | **CameraAttributesPractical far DOF**（24 m 起，过渡 18 m，强度 0.08） | 3D 背景轻微虚化，像素主角更突出 |
| 暗角 | 无 | `shaders/post_vignette.gdshader`（strength 0.45） | 收拢画面注意力 |
| 树木高度 | 手摆 4.4–5.6 / 散布 3.6–5.4 / 树环 5.0–7.5 m | **3.2–4.2 / 2.8–4.2 / 4.5–6.0 m** | 初版树在画面里过大，压住主角 |
| 花 | 18+10 朵 | **55+20 朵** | 增加草地细节 |
| 材质修复 | — | Kenney GLB 逐面重着色：`metallic = 0`、`roughness = 1`、薄荷绿叶相 → 草绿、浅木色 → 树皮棕 | glTF 默认 metallic=1 导致树青色反光；详见 `_mesh_with_tinted_surfaces()` / `_tint_material()` |

树叶/木头的调色在 `_tint_material()` 里用 HSV 判断：色相 0.36–0.58 视为薄荷绿→改到 0.27 并压暗；色相 <0.12 且亮度 >0.6 的浅木色压暗成树皮棕。`PROP_TINT` 仍在你原来的暖色调上。
