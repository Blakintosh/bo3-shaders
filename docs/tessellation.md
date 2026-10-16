# Tessellation, displacement and parallax

Hardware tessellation, displacement and parallax for BO3 world geometry and models. The files are in this repo's
`shaders/blak/` and `techsets/` (`./sync.sh` installs them into the game and tools sets); the test materials
(`zz_tess_test.gdt`) are in `bo3-linker-patches`.

| Techset | What |
|---|---|
| `lit_advanced_fullspec_parallax` | the parallax material (POM only) |
| `lit_advanced_fullspec_parallax_tess` | the parallax material, tessellated and displaced |
| `lit_advanced_fullspec_blend_tess` | two layers blended by vertex alpha and their heights, tessellated, displaced and parallaxed |
| `lit_advanced_fullspec_blend2_tess`, `blend3_tess`, `blend4_tess` | 2/3/4 layers picked by vertex colour (R, G, B), alpha scales the displacement (see below) |
| `lit_decal_reveal_conform`, `lit_decal_conform` | brush/patch decals that follow whatever is rendered under them (see Decals) |
| `lit_decal_reveal_tess` | a reveal decal displaced with its host's height map (older; prefer the conform decals) |

| File | Role |
|---|---|
| `blak/blak_tess_common.hlsl` | local + hull shaders, domain helpers, the material controls (documented at the top) |
| `blak/tess_blend.h` | the layer blend shared by the blend DS, shadow DS and PS |
| `blak/tess_triplanar.h` | world-mode box mapping for the pixel shaders |
| `blak/blak_gbuffer_tess_lit_parallax.hlsl`, `blak_gbuffer_tess_lit_blend.hlsl` | gbuffer domain shaders |
| `blak/blak_gbuffer_ps_lit_parallax.hlsl`, `blak_gbuffer_ps_lit_blend.hlsl` | the parallax and blend pixel shaders |
| `blak/blak_shadow_tess.hlsl` | tessellated, displaced shadow pass |
| `blak/blak_gbuffer_vs_lit_parallax.hlsl`, `gbuffer_vs_lit_tools.h` | the parallax VS (game; the tools build uses the shared tools VS) |
| `blak/blak_gbuffer_tess_decal_conform.hlsl`, `blak_gbuffer_tess_decal.hlsl` | decal domain shaders |
| `blak/tess_overlay_wireframe.hlsl` | tools only: the TessTopology plugin's selection wireframe (compiled to `.cso`, not by a techset) |
| `include/blak_tess_base`, `blak_tess_decal_base`, `blak_parallax_base` | shared controls, the `patch3` primitive type, LS/HS blocks |

Game and tools differences live in the same file under `TOOLSGFX` (`#if TOOLSGFX` in HLSL, `#if TOOLSGFX == "1"` in
techsetdefs, as the stock techsets do).

## Radiant / APE
`shaders_stable_toolsgfx` and `techsetdefs_stable_toolsgfx` hold the tools versions, which tessellate in Radiant like
the game does. Requirements, all found 2026-10-10:
- the `mtplugins/TessTopology` plugin (Patch topology + indexCount, as the linker feature does); Radiant's pass binder
  already binds the hull and domain shaders and the patch topology once the pass is valid;
- `vertexDecl = "generic"` on the local shader under `TOOLSGFX` (see `include/blak_tess_base`): Radiant
  builds a pass's input layouts from `vertexDecl`, and without one the binder bails out silently (this, not a missing
  HS/DS bind, is why tessellated passes drew nothing);
- every shader a techset names must exist in `shaders_stable_toolsgfx` (`blak/blak_shadow_tess.hlsl` was missing, which
  made the techset fail to register).
`blak_tess_common.hlsl`, `tess_blend.h` and the gbuffer domain shaders are the same files in both trees (`TOOLSGFX`
switches the camera to `gScene.wldCameraPosition`, skinning to the tools' own check, and drops motion vectors).

## Requirements

- The tessellation linker feature. Dragon has it built in and on by default. With the stock linker, install the
  bo3-linker-patches hook and set `"tessellation": true` in the map's `linker.json`. Without it nothing tessellated
  draws.
- Spacing, near and far are material settings only when Dragon links the map (it stores the local shader's
  constants). Stock leaves that constant group empty and the game doesn't rebind it, so a stock-linked local shader
  reads a stale buffer (in testing: the previous zone's values). Out-of-range values fall back to `TESS_SPACING` /
  `TESS_NEAR` / `TESS_FAR` (8 / 256 / 2048), but on stock-linked maps don't rely on the material's values.
- Radiant / APE: the TessTopology MTPlugin (bo3-linker-patches `mtplugins/TessTopology`); without it tessellated
  surfaces don't draw in the editors.
- Optional: the cod2map hook (bo3-linker-patches `cod2map/`) for bullet collision that follows displaced patches.

## Controls

| GDT field | Control |
|---|---|
| `cg10_x` | vertex spacing up close, units (Dragon only) |
| `cg10_y` | displacement height, units (0 = flat) |
| `cg10_z` | displacement midpoint (0..1) |
| `cg10_w` | debug: 1 tint per vertex, 2 heat map of the factor (red 1, green 16, blue 32+), 3 alpha ramp along X |
| `cg11_x`, `cg11_y` | full detail within / nothing beyond, units (Dragon only) |
| `cg11_z` | world mapping: units per repeat (0 = mesh UVs) |
| `cg13_x` | world mapping axis: 1 X, 2 Y, 3 or 0 Z (negative pushes the other way) |
| `cg13_y`, `cg13_z` | anchor plane (world coordinate on the axis) and its fade (units, 0 = none) |
| `cg11_w` | vertex alpha scales the displacement: 0 off, 1 = 0..1 (alpha 0 flattens), 2 = -1..1 (0.5 flat, 0 inverts), 3 = 0..2 (0.5 unchanged, 1 doubles). `cg10_w` = 3 previews it as an alpha ramp along world X without painting |
| `cg12_x`, `cg12_y` | blend: softness (0 = 0.2), layer 2 height strength (0 = flat, 1 = as authored) |
| `cg12_z`, `cg12_w` | blend3/4: layer 3 / layer 4 height strength |
| `colorMap09`..`13` | blend layer 2: colour, normal, specular, gloss, height |

- Mesh mode pushes along the normal: right for patches, terrain and smooth models; hard edges open up.
- World mode samples the height from the world plane across the chosen axis and pushes along that axis for every
  face, so nothing cracks, hard edges and box corners included (Z for floors and terrain, X/Y for walls). Textures
  are box-mapped (each face projects onto the plane it faces most), so side faces aren't streaked. The anchor plane
  pins the displacement to 0 there (a floor's underside, a wall's back face), still by position only.
- The height is sampled at the mip whose texels match the local vertex spacing, so detail finer than the mesh
  doesn't alias into zigzags and spikes (it stays in POM and the normal map). The inside factor is the longest
  edge's, which spreads vertices across sliver triangles.

## Verified in game (2026-10-09, `zm_repl`)

- Tessellation, displacement and distance falloff; heat map follows the material's spacing with Dragon (32 -> ~8,
  16 -> ~16 on a 256-unit edge).
- World mode: the slab's top and sides are one crack-free surface; with the anchor its bottom stays on the floor and
  box mapping textures its sides. World mode along -Y closes the stone panel's corners (the mesh-mode holes) and the
  matched mip removes the zigzag aliasing on its narrow side face.
- Blend: layer 2 comes in by the debug alpha ramp, each layer displaced by its own height, the taller winning.
- Tessellated shadows match the displaced outline.
- Volume decals (`misc_volume_decal`) project onto the displaced surface, on floors and walls: no tessellated
  brush-decal technique is needed.

## Gotchas found on the way

- The `Include/` SDK skins every vertex in game (`Utility_HasBones` is always true); world vertices have no bone
  weights, so skinning makes NaNs and nothing draws. Skinning is gated on `USE_GPU_SKIN` (1 for `mc/`, 0 for `wc/`).
  `gbuffer_vs_lit_parallax.hlsl` had the same problem and didn't compile for `wc/`; fixed (original kept as
  `.pre_fix.bak` in the game folder).
- `outputtopology("triangle_cw")` is BO3's front face.
- The game binds material/code resources to the VS, PS and DS stages only; material constants reach the DS
  (group 0 of the material's static constant buffers) and, Dragon only, the LS (group 1).
- The stock `wireframe` technique can't be overridden (the first Technique definition wins), hence the debug tints.
- Materials only link with a prefix (`wc/`, `mc/`): Treyarch's shadow/unlit shaders aren't cached unprefixed.

## World-mode normals and triplanar texturing
In world mode the domain shaders output the displaced surface's normal (finite differences of the displacement, a step
of half the local vertex spacing) and a matching tangent frame, so lighting follows the relief. The pixel shaders then
texture with `blak/tess_triplanar.h`: every map is sampled on the three world planes (the domain shader's planes and
`tessWorldScale`) and blended by that normal, normal maps rotated into world space per plane, so slopes no longer smear
the texture. Parallax is skipped in this mode. Mesh mode (`tessWorldScale` = 0) is unchanged. The tools default vertex
spacing is 4 (the editors can't read the spacing control); the game's is 8 unless set in the material (Dragon).


### Radiant's compiled-shader cache
Radiant (and APE) keep compiled shaders in `share\assetconvert\ToolsGfx\shaders_modtools\v14\<xx>\<source>.hlsl\` and did not pick up edits to a shader's source here (2026-10-10: edits to tess_common, the domain shaders and the pixel shaders were ignored until their cache folders were deleted). After editing a tools shader, delete that shader's folder (and those of the files that include it) before restarting the editor.

### Vertex-colour blends (`blend2_tess`, `blend3_tess`, `blend4_tess`)

Each extra layer has its own colour, normal, specular, gloss and height maps and comes in as you paint its vertex
colour channel down from white: R for layer 2, G for layer 3, B for layer 4. Unpainted (white) is layer 1. Layers stack
in that order, so where several channels are painted the later one wins; each step is a height blend (the taller layer
wins at the transition; softness `cg12_x`) and each layer displaces with its own height map, scaled by its strength
(`cg12_y`/`z`/`w`). Vertex alpha is free for the displacement scale: `cg11_w` defaults to 0..1 in these techsets (2
and 3 work as elsewhere). The vertex colour no longer tints the albedo. Layer 2 maps are `colorMap09`-`13`, layer 3
`colorMap00`-`04`, layer 4 `colorMap05`-`07`, `14`, `15` (that uses up the generic slots; 4 layers is the ceiling).
Brushes carry no painted colour: use patches or terrain. `blend_tess` (two layers by alpha) is unchanged.

Verified in game (2026-10-16): a 5x5 patch painted white / R / G / B / white across and alpha 1 to 0 along shows the
four layers in order with height-shaped transitions, and the relief fading out towards alpha 0.

## Decals over tessellated surfaces

### Conforming decals (preferred): `lit_decal_reveal_conform`, `lit_decal_conform`

`decal/lit_decal_reveal_conform.techsetdef` is `lit_decal_reveal` with its gbuffer pass tessellated, and each
generated vertex slides along the decal's normal onto the surface the camera sees, found in the scene depth
(`CodeTexture( "floatZSampler" )`, the opaque depth the engine copies before the decal pass; the game binds code
textures to the domain shader). The decal takes the height of whatever is under it: any tessellated host, world or
mesh mode, brush, patch, terrain or model, with no host settings and the stock tint mask. The stock reveal pixel
shader runs unchanged, so painted vertex alpha still blends (`blak/blak_gbuffer_tess_decal_conform.hlsl`).

- `cg10_y`: search range, units either side of the decal face (cover the host's relief; 0 = 16).
- `cg13_w`: depth bias, units. It pulls each vertex towards the camera along its view ray, so the decal never moves on
  screen; it only has to cover the host poking through between the two meshes' vertices. 1 was enough on the 40-unit
  wall with the decal at a fixed 3-unit spacing (`TESS_SPACING_FORCE` on its local shader).
- `cg10_w` 4 / 5: debug colours (red = surface not found; blue..yellow = bottom..top of the range / position within a
  search step).
- The game's scene viewport maps depth into [0, 63/64] (MaxDepth 0.984375 on world and decal draws), so the depth
  buffer holds z/w × 63/64; the search scales its own depth the same way. Without that every vertex lands 1.6% of its
  distance behind the surface.
- Points the camera can't see (off screen, behind something, behind the viewmodel) keep the flat position; whatever
  hides them hides the decal there too.
- `lit_decal_conform` is the same for `lit_decal` (no reveal map). Both verified in game and in Radiant (2026-10-16).
- In Radiant the TessTopology MTPlugin binds the scene depth (the tools give a domain shader no code textures); without it the decal draws flat.

Verified in game (2026-10-15): the ice-waves test decal on the 40-unit wall covers its whole area following every
bump, from the front, at a grazing angle (the rock in front still hides it), and from ~900 units.

### Host-matched decals: `lit_decal_reveal_tess`

`decal/lit_decal_reveal_tess.techsetdef` runs a stock decal pixel shader (Treyarch's `gbuffer_decal.hlsl`, unchanged,
with its stock defines: its source isn't on disk, only precompiled variants, so changing the defines breaks the
link) behind `blak/blak_gbuffer_tess_decal.hlsl`, a domain shader that emits what the stock decal vertex shader emits
(COLOR0 = vertex colour^2.2, COLOR1 = vertex alpha; until 2026-10-15 it sent alpha 0, which broke painted reveal
blends). The decal's vertices then follow the same displacement as the surface under it.

- Give the decal material the host's tessellation controls in world mode (`cg10`-`cg13`) and the host's height map
  in its **tint-mask slot** (`colorMap00`). The domain shader reads that slot; the stock tint mask is therefore
  replaced by the height image, so keep `colorTint` white. (A separate `heightMap` texture, or any texture declared
  before the stock ones, shifts or hijacks the stock slots and corrupts the decal's shading.)
- `cg13_w` lifts the decal off the surface (units). The decal and the host are different meshes, so between their
  vertices the host can poke through the decal; a lift of about 0.8 hid that at 40 units of displacement.
- Mesh mode can't match (the decal's UVs aren't the host's).
- A material's techset or flags only change after a full map build (`bo3h map --full`); a relink alone keeps the old
  data, and a changed GDT needs the gdtDB to refresh first (a failing `gdtdb /update`, for example on duplicate
  GDTs, leaves it stale).
- **Volume decals** (`misc_volume_decal`, and the `vd/`/`vdd/` variants bullet impacts use) project onto scene depth,
  so they follow the displaced surface of any tessellated host (brush, patch, model, world or mesh mode) with no
  tessellated techset and no extra cost. This is the general route for decals, reveal decals and impact decals; make
  the volume deep enough to contain the relief (depth >= displacement + margin). The `_tess`/`_conform` decal
  techsets are for brush-face and patch decals.
- **Bullet impacts** are volume decals too, but the FX makes each one a cube about 3 units across (half-extent ~3,
  read from `volDecalInstanceBuffer` in RenderDoc), centred where the bullet trace hit the collision, which is the
  flat, undisplaced surface. Relief within ~3 units of that (the cobble test: 4 units, midpoint 0.8) shows marks;
  deeper relief (the 40-unit wall) gets none. Fixes: put the hit on the displaced surface (`cod2map/` for patches, `runtime/tess_trace`, box
  brushes only so far), or an engine patch that deepens FX volume decals.

Verified in game: a brush decal on a 40-unit displaced wall follows the relief across the patch, and a
`misc_volume_decal` (80-unit deep) covers the same wall following every crevice.

### Flattening or inverting the height with vertex alpha

`cg11_w` (`tessMask`) scales the displacement by vertex alpha, for patches, terrain and models that carry painted
alpha (and for the decals over them): flatten the relief to 0 where a surface meets another, double it on a ridge or
invert it. Brushes carry no painted alpha; use the anchor plane (`cg13_y`/`cg13_z`) or `cg10_w` = 3 to preview. Seen in
game with the preview ramp (alpha 1 at x = 0, 0.5 at x = 64, 0 at x = 128, 256 repeat): mode 1 flat at the ends and
full in the middle, mode 2 inverted at the ends, mode 3 twice as deep in the middle; a decal over it follows.

## Collision for displaced surfaces

For patches, use the cod2map hook (`cod2map/`, verified in game 2026-10-16). It compiles a bullet-only collision patch
that follows the displaced surface of every tessellated patch, and leaves the flat patch to movement only, so impacts
land on the relief. Install it once, add `tess_shot.gdt` and set `"tessellation": true`. For brushes:

For bullets and other line traces, prefer `runtime/tess_trace` (a trace hook plus a baked side file: nothing is added to
the map). The brush-baking tool below is for when players and AI must collide with the relief too.

`tools/tess_collision.py <map> --gdt <gdt>` bakes collision prisms under the displaced surface of axis-aligned
`parallax_tess` box brushes (world mode), so bullets, players and AI meet the surface you see.

- The prisms go in their own `script_brushmodel` entity. In worldspawn they are merged into the world's visibility
  and cut away any decal brush that lies inside them at compile time.
- Add a `tess_collision` material (a copy of `caulk` without the caulk flag: `noDraw 1`, `umbraOccluder 0`,
  `noCastShadow 1`, the clip flags `playerClip aiClip vehicleClip playerVehicleClip bulletClip missileClip itemClip
  canShootClip utilityClip` set, and the host's `surfaceType`). Set the host material `nonColliding` so the flat
  brush stops colliding.
- Run it before the compile; it rewrites its own section on each run. `--cell` is the cell size (default 8).

`--strip` removes the generated section again.

Verified in game with `BulletTrace` (and with the harness's `impact` command, which traces and plays the stock bullet
impact fx at the hit: positions y = 187 to 199, normals such as (0.32, -0.73, 0.60), where the flat wall gives
(0, -1, 0) at y = 200) along +Y columns through a wall displaced 40 units: the hits land at y = 186.6 to
199.1 instead of the flat plane (200), within about 10 units of the height map's prediction (the collision is a
coarser mesh than the GPU's; the error scales with the displacement).
