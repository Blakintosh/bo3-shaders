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
surface terms: Fresnel, a reflection taken from the scene, a GGX highlight, and albedo dirt.

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

## Credits

These shaders were derived from works by [Scobalula](https://github.com/Scobalula) and [LG](https://github.com/LG-RZ).

## License

MIT, see [LICENSE](LICENSE).
