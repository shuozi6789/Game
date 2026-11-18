# Kenney Nature Kit 2.1

- **Author:** Kenney (https://www.kenney.nl)
- **Source:** https://kenney.nl/assets/nature-kit
- **License:** Creative Commons Zero (CC0 1.0) — public domain, free for personal/commercial use.
  Full text: https://creativecommons.org/publicdomain/zero/1.0/ (also bundled as `License.txt`)
- **Version / date:** Nature Kit 2.1, creation date 2020-04-29
- **Contents:** 329 low-poly nature models in `models/` as self-contained **GLB** (`*.glb`), plus
  `preview.png` (contact sheet) and the original `License.txt`.
- **Crediting:** not mandatory under CC0, but attribution to Kenney is appreciated.

## Notes for this project

Models are suitable for the HD2D grass field: `tree_default.glb`, `tree_oak.glb`, `tree_pineTallA.glb`,
`grass.glb`, `grass_large.glb`, `rock_*.glb`, `cliff_*.glb`, `plant_bush.glb`, `flower_*.glb`, etc.
They have no collision shapes — add `StaticBody3D` collisions only where gameplay needs them, and use
`MultiMeshInstance3D` for grass/rock scattering to keep draw calls low. Keep material/texture filtering
at nearest for the pixel-art look.
