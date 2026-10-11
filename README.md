# bo3-shaders

A collection of custom shaders I use in Black Ops III.

Feel free to use/adapt these. I'll share ones from time to time, but note that I focus on my own personal use and may not be able to offer support.

```
shaders/   -> share/raw/shaders_stable  and  shaders_stable_toolsgfx      (one source for game and tools)
techsets/  -> share/raw/techsetdefs_stable  and  techsetdefs_stable_toolsgfx
```

- `./sync.sh [bo3 root]` copies everything into both the game and tools sets.
- `./compile_check.sh [shader]` compiles every variant with fxc against the install's includes: game and tools,
  `mc/` (skinned) and `wc/` (world), and OIT. Run it before linking.

## Frosted glass (`blak_frosted_glass`, `blak_frosted_glass_world`)

Glass or polymer drawn in one pass. It shows the scene behind refracted through the normal map and blurred
(Vogel disc, radius x thickness x roughness), tinted by a transmission map and darkened by thickness. On top go the
surface terms, lit the way the stock lit shaders light a surface: the reflection comes from BO3's reflection probes
(box-projected local probes over the global probe, weighted by the stock env BRDF) and the albedo dirt from the probe
irradiance volumes. A GGX key-light highlight sits on top. Where no probe data is bound (APE), the reflection falls
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
## Probe lighting (`blak/blak_lighting.h`)

BO3's forward probe lighting for custom lit or transparent shaders, reversed from the stock `lit_transparent` pixel
shader (and the deferred lighting shader, which runs the same code). It covers the tiled probe culling, override
probes, attenuation volumes, box-projected reflections, the diffuse probe volumes, the global probe fallback, the
Toksvig gloss filter and the env BRDF. Call `Blak_ProbeLighting()` and scale the result by `BLAK_OUTPUT_SCALE`.

- Game: the linker binds the lighting resources by name (`refProbeConstants`, `visibleProbes`,
  `gReflectionProbeArray`...), so the technique only declares the shared `samplerLinear` / `samplerLinearClamp`.
  Keep your material textures and samplers off its registers.
- Tools: APE and Apex bind the tools' names (`gProbes`, `gProbeCullResults`...); APE's preview has only the global
  probe.

Checked in game against stock `lit` on the same mesh under the same probes: under the global
probe and inside a local probe's box, both within ~10% (the rest is the stock material's other lighting terms).

## License

MIT, see [LICENSE](LICENSE).
