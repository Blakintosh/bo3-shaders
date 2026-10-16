# bo3-shaders

A collection of custom shaders I use in Black Ops III.

Feel free to use/adapt these. I'll share ones from time to time, but note that I focus on my own personal use and may not be able to offer support.

```
shaders/                    -> share/raw/shaders_stable  and  shaders_stable_toolsgfx   (one source for game and tools)
deps/shaders_stable/        -> share/raw/shaders_stable            (shared headers, game copy)
deps/shaders_stable_toolsgfx/ -> share/raw/shaders_stable_toolsgfx (shared headers, tools copy)
techsets/                   -> share/raw/techsetdefs_stable  and  techsetdefs_stable_toolsgfx
```

Everything installs one folder deep under `blak/`, which keeps it apart from other packs on disk and in the game's
shader cache (keyed by the full path and the content). Radiant and APE key their cache by bare file name, so every
file a techset compiles (`source = ...`) carries the `blak_` prefix; include-only files don't need it (they're never
cached by name) and are `.h`, with `BLAK_` include guards. Includes go one folder deep (`blak/x.h`): a deeper one
failed to open in the stock linker. Game and tools differences live in one file under `TOOLSGFX` (`#if TOOLSGFX` in
HLSL, `#if TOOLSGFX == "1"` in techsetdefs, as the stock techsets do).

- `./sync.sh [bo3 root]` copies the shaders, headers and techsets into both the game and tools sets.
- `./compile_check.sh [shader]` compiles every variant with fxc straight from the repo (no install needed): each entry
  point the file has (local, hull, domain, vertex, pixel), game and tools, `mc/` (skinned) and `wc/` (world), OIT, and
  the blend layer counts. Run it before linking.

The shared headers (`blak/blak_common.h` and what it includes: transforms, skinning, the game and tools constant
buffers) are community headers built from the Mod Tools' shaders (see Credits), renamed and with their include guards
prefixed. The game and tools copies differ, so each set has its own.

## Tessellation, displacement and parallax

`lit_advanced_fullspec_parallax` (POM), `lit_advanced_fullspec_parallax_tess` (tessellated and displaced),
`lit_advanced_fullspec_blend_tess` (two layers by vertex alpha) and `lit_advanced_fullspec_blend2_tess` /
`blend3_tess` / `blend4_tess` (2-4 layers by vertex colour, alpha scales the height), plus the decals that follow
them: `lit_decal_reveal_conform`, `lit_decal_conform` and `lit_decal_reveal_tess`. They need the tessellation linker
feature (built into Dragon; the stock linker needs the bo3-linker-patches hook) and, to show in Radiant / APE, the
TessTopology MTPlugin. Controls, modes and what was verified: [docs/tessellation.md](docs/tessellation.md).

## Frosted glass (`blak_frosted_glass`, `blak_frosted_glass_world`)

Glass or polymer drawn in one pass. It shows the scene behind refracted through the normal map and blurred
(Vogel disc, radius x thickness x roughness), tinted by a transmission map and darkened by thickness. On top go the
surface terms, lit the way the stock lit shaders light a surface: the reflection comes from BO3's reflection probes
(box-projected local probes over the global probe, weighted by the stock env BRDF) plus the shadowed sun's specular,
and the albedo dirt from the probe irradiance volumes and the sun. An optional camera-relative key-light highlight
sits on top (Highlight Strength 0 turns it off). Where no probe data is bound (APE), the reflection falls
back to the blurred scene around the part.

| techset | use on | game render flags |
|---|---|---|
| `blak_frosted_glass` | viewmodel parts (MW see-through mags) | emissive + current resolve |
| `blak_frosted_glass_world` | world brushes (`wc/`) and world models | `lit transparent distortion` |

Both share the shader and the material fields (`include/blak_frosted_glass_base`). They differ only in render flags.
World draws with the viewmodel's emissive flags read `resolvedPostSun` before that frame's resolve and come out
black or stale. In APE / Apex both draw as transparents through `oit`. Apex binds the lit opaque scene to
`iResolveScene`; APE binds nothing, so in APE the glass is lit from a flat mid grey (no see-through). [Apex](https://github.com/Blakintosh/apex) 0.3+ can render this.

Refraction projects the bent ray through the draw's own view-projection, so it holds for the viewmodel FOV and
for world glass at any distance. `cg01_w` is the depth behind the surface in world units: ~0.5 for a mag, 2-8 for a
window.
## Probe and sun lighting (`blak/blak_lighting.h`)

BO3's forward lighting for custom lit or transparent shaders, reversed from the stock `lit_transparent` pixel shader
(the deferred lighting shader runs the same probe code):

- `Blak_ProbeLighting()`: tiled probe culling, override probes, attenuation volumes, box-projected local reflection
  probes, the diffuse probe volumes and the global probe fallback. `Blak_EnvBRDF()` and `Blak_ToksvigGloss()` are the
  stock env BRDF and gloss filter.
- `Blak_SunLighting()`: the sun's GGX specular and diffuse. `Blak_SunShadow()`: the stock sun shadow lookup (the
  three cascades, with the translucent shadow map and the dithered option in game, and the static sun shadow tree
  beyond them). `Blak_PlayerSunShadow()`: the game's extra projected shadow around the player, for the viewmodel and
  the world.

Results are in lighting units: scale them by `BLAK_OUTPUT_SCALE`.

- Game: the linker binds the lighting resources by name (`refProbeConstants`, `visibleProbes`, `gReflectionProbeArray`,
  `gSunShadowTree`, `gSunShadowmapArray`, `lightConstants`, `gSpotShadowmapArray`, `ShadowSamplerComparisonState`...), so the technique only declares the shared
  `samplerLinear` / `samplerLinearClamp`. Keep your material textures and samplers off its registers.
- Tools: APE and Apex bind the tools' names (`gProbes`, `gProbeCullResults`...). APE's preview has only the global probe.

Checked in game (zm_repl) against the stock `lit_transparent` shader (the forward path this ports): the same mesh (the
riot shield body), the same albedo and the same camera, linear frost/stock over the mesh:

| where | frost / stock | median per-pixel difference |
|---|---|---|
| global probe, facing the sun | 1.001 | 0.000 |
| global probe, inside a cast shadow | 1.002 | 0.000 |
| local probe box, facing the sun | 0.99 | 0.002 |
| local probe box, facing away | 0.99-1.03 | 0.012 |
| viewmodel (riot shield inner plate, sunlit, player shadow live) | 1.000-1.001 | 0.000 |

At the same spot as the local-probe rows, frost against stock deferred `lit` was 0.97-0.98 (deferred and forward stock
agree to within 1% on this mesh). On the M13 mag's rounds the frost came out 10-20% darker than stock deferred inside
the local probe's box, which these tests don't explain.

## Credits

These shaders were derived from works by [Scobalula](https://github.com/Scobalula) and [LG](https://github.com/LG-RZ).

## License

MIT, see [LICENSE](LICENSE).
