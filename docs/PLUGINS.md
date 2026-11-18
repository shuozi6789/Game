# 工具与插件：提升模型和场景质量

> 结论先说：Godot 本身不是建模软件，**没有任何 Godot 插件能把程序化方块自动变成高精度模型**。要明显提升质量，需要换“资产管线”：用 Blender/AI 生成或下载现成 glTF 模型，再导入 Godot。下面的插件负责**摆放、地形、植被、相机、对话、测试**，不负责把 primitive 变成角色。

## 当前项目已安装的插件

| 插件 | 状态 | 用途 |
| --- | --- | --- |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) 0.11.0.4 | 已启用 | 相机切换、跟随、对话/第一人称镜头 |
| [Aseprite Wizard](https://github.com/viniciusgerevini/godot-aseprite-wizard) 9.8.0 | 已启用 | Aseprite 像素图导入、动画切帧 |
| [Dialogic](https://github.com/dialogic-godot/dialogic) 2.0-alpha | 已安装、未启用 | 分支对话/演出；当前项目用的是自写对话系统 |
| [Gut](https://github.com/bitwes/Gut) 9.7.1 | 已安装、未启用 | GDScript 单元测试 |

这些插件对“模型精度”没有直接帮助。

## 推荐：人物与木偶

### 1. Blender + MPFB2（免费，性价比最高）

- [MPFB2](https://github.com/makehumancommunity/mpfb2)：Blender 里的 MakeHuman 插件，可生成带骨骼、可调体型/人脸/服装的人形网格；
- [Humanizer](https://github.com/sagersmith8/Humanizer)：把 MPFB2 角色转换到 Godot 4 的桥接插件；
- **Rigify**（Blender 自带）：做木偶/人形的可动画骨架；
- **Mixamo**：免费动作库，走路、待机、交谈、挥手都有，可导出带骨骼动画的 FBX/glTF。

适合本项目的做法：

1. 用 MPFB2 做 8 个 NPC 和木偶人的基础体型；
2. 在 Blender 里加木偶球关节、心形胸腔、服装/帽子；
3. Mixamo 绑动作，导出 `.glb`；
4. 替换 `npc.gd` / `vision.gd` 里的程序化 primitive。

这条路工作量最大，但人物质量会有质变。

### 2. AI 图生 3D（最快出高模）

- [Meshy](https://www.meshy.ai/)
- [Tripo](https://www.tripo3d.ai/)
- [CSM](https://csm.ai/)

把已经生成的 2D 立绘/木偶设计图丢进去，生成带贴图的 3D 网格，再在 Blender 里清理拓扑、减面、绑骨，导出 glTF。
适合做**道具、木雕、建筑构件、NPC 半身像**；人物全身动画仍建议手工绑定。免费额度/商用授权要在使用前确认。

### 3. 现成免费低模（最快，风格统一）

- [Quaternius](https://quaternius.com/)：CC0 低多边形人物、动物、建筑、道具；
- [Kenney](https://kenney.nl/assets)：CC0 游戏资产，本项目已经在用它的自然套件；
- [Poly Haven](https://polyhaven.com/)：CC0 HDRI、PBR 材质、模型。

如果要保持现在的低模风格，**换 Quaternius 的角色/建筑模型**比继续堆 primitive 有效得多。

## 推荐：场景与关卡

| 插件/工具 | 用途 | 链接 |
| --- | --- | --- |
| **Terrain3D** | 雕刻地形、纹理层、大世界地形；替代现在手写的高度场 | [Terrain3D](https://github.com/TokisanGames/Terrain3D) / [Asset Library](https://godotengine.org/asset-library/asset/3134) |
| **ProtonScatter** | 用画笔撒草、树、石头、花，比手写 MultiMesh 快 | [ProtonScatter](https://github.com/HungryProton/scatter/releases) |
| **Godot Asset Placer** | 在 3D 场景里批量摆放/对齐建筑、道具 | [Asset Library](https://godotengine.org/asset-library/asset/4244) |
| **Godot Jolt** | 更稳定的物理（碰撞、角色、可破坏物） | Asset Library 搜索 Jolt |
| **Dialogic**（已安装） | 分支对话和过场演出；如果以后剧情分支变复杂再用 | 已安装 |

注意：Terrain3D/ProtonScatter 是 GDExtension/版本敏感插件，安装前要确认 release 支持 **Godot 4.7**；不要直接覆盖现有地形，先在一个测试场景里验证。

## 对当前项目的建议优先级

1. **先换人物**：木偶人 + 8 NPC 从 primitive 改为 glTF 模型，视觉提升最大；
2. **再换近景道具**：木匠家、NPC 建筑、木雕换成现成 glTF/Blender 资产；
3. **再做地形/植被**：如果还要扩大草坡，再上 Terrain3D + ProtonScatter；
4. **最后才上 Asset Placer**：它只是摆放工具，不改变资产本身质量。

## 已实施的路线 A

- NPC 身体已替换为 **Kenney Blocky Characters 2.0**（CC0，18 皮肤 / 27 动画），保留原有建筑/道具与对话。
- 木匠家家具已替换为 **Kenney Furniture Kit**（CC0）的床、桌椅、书架、长凳、衣帽架、纸箱、落地灯。
- 资源位于 `assets/free/kenney_blocky_characters/` 和 `assets/free/kenney_furniture/`，各自带 LICENSE。
- 木偶主角需要心形凹槽/特殊关节，暂保留定制模型，作为路线 B 的重点。

## 我可以直接做的下一步

- **路线 A（快）**：下载 Quaternius/Kenney 免费 glTF，把木匠家/NPC 建筑/木偶人替换为 real assets，保留现有玩法和数值；
- **路线 B（质量优先）**：先做 Blender + MPFB2 的木偶人样板，导入 Godot 验证骨骼/材质/动画，再批量做 NPC；
- **路线 C（AI）**：用 Meshy/Tripo 生成木雕和建筑构件，人工清理后导入。

你选一条，我再开始改项目；第三方插件不会在你确认前强行装进工程。
