// Layer blend shared by the blend techsets' domain, shadow and pixel shaders, so the displaced shape, its shadow and the
// texturing agree. Needs heightMap, heightMap2 (and heightMap3/4 for 3/4 layers), aoSampler and tessMid declared
// before the include.
//
// lit_advanced_fullspec_blend_tess (BLEND_RGB_LAYERS undefined): two layers, vertex alpha picks: 1 (what unpainted
// brushes have) is layer 1, painting it down brings layer 2 in.
// lit_advanced_fullspec_blend2/3/4_tess (BLEND_RGB_LAYERS 2/3/4): vertex colour picks, one channel per extra layer:
// painting R down brings layer 2 in, G layer 3, B layer 4 (white, i.e. unpainted, is layer 1). Layers stack in that
// order, so where several are painted the later channel wins. Alpha is left to scale the displacement (tessMask,
// 0..1 by default in these variants), and the vertex colour no longer tints the albedo.
//
// Each step's weight is sharpened by the heights (a height lerp: the taller layer wins at the transition);
// tessBlendContrast is how soft that is (0 = 0.2). Layer N's height is pulled towards tessMid by tessLayerNHeight
// (0 = flat at the midpoint, 1 = as authored): a flat layer brings the displacement smoothly down to nothing where it
// takes over, instead of cutting it off.
//
// Material controls: cg12 x tessBlendContrast, y tessLayer2Height, z tessLayer3Height, w tessLayer4Height.

#ifndef BLAK_TESS_BLEND_H
#define BLAK_TESS_BLEND_H

float tessBlendContrast;
float tessLayer2Height;
float tessLayer3Height;
float tessLayer4Height;

#if BLEND_RGB_LAYERS
#define BLEND_LAYERS BLEND_RGB_LAYERS
#else
#define BLEND_LAYERS 2
#endif

// Weight of layer 2 for heights h1, h2 (0..1) and vertex alpha.
float BlendWeight(float h1, float h2, float alpha)
{
	float a = 1.0 - alpha;
	float contrast = tessBlendContrast > 0 ? tessBlendContrast : 0.2;
	return saturate(((h2 + 2.0 * a - 1.0) - h1) / contrast + 0.5);
}

// The blended height for displacement and parallax.
float BlendedHeight(float h1, float h2, float w)
{
	return lerp(h1, lerp(tessMid, h2, saturate(tessLayer2Height)), w);
}

// The paint channel of layers 2, 3, 4 (1 = unpainted): vertex RGB in the RGB variants (none painted, all 0, counts as
// white), else alpha for layer 2.
float3 BlendSelector(float3 rgb, float alpha)
{
#if BLEND_RGB_LAYERS
	return dot(rgb, 1.0) <= 0 ? float3(1, 1, 1) : rgb;
#else
	return float3(alpha, 1, 1);
#endif
}

// Weights of layers 2, 3, 4 (each over what is below it) for heights h (layers 1-4) and selector sel; height gets the
// blended height.
float3 BlendWeights(float4 h, float3 sel, out float height)
{
	float hc = h.x;
	float w2 = BlendWeight(hc, h.y, sel.x);
	hc = lerp(hc, lerp(tessMid, h.y, saturate(tessLayer2Height)), w2);
	float w3 = 0, w4 = 0;
#if BLEND_LAYERS >= 3
	w3 = BlendWeight(hc, h.z, sel.y);
	hc = lerp(hc, lerp(tessMid, h.z, saturate(tessLayer3Height)), w3);
#endif
#if BLEND_LAYERS >= 4
	w4 = BlendWeight(hc, h.w, sel.z);
	hc = lerp(hc, lerp(tessMid, h.w, saturate(tessLayer4Height)), w4);
#endif
	height = hc;
	return float3(w2, w3, w4);
}

// A map's value through the layer stack: BLEND_SAMPLE(colorMap, colorSampler, uv, w) blends colorMap, colorMap2... by w.
#if BLEND_LAYERS >= 4
#define BLEND_SAMPLE(t, smp, uv, w) lerp(lerp(lerp(t.Sample(smp, uv), t##2.Sample(smp, uv), (w).x), t##3.Sample(smp, uv), (w).y), t##4.Sample(smp, uv), (w).z)
#elif BLEND_LAYERS >= 3
#define BLEND_SAMPLE(t, smp, uv, w) lerp(lerp(t.Sample(smp, uv), t##2.Sample(smp, uv), (w).x), t##3.Sample(smp, uv), (w).y)
#else
#define BLEND_SAMPLE(t, smp, uv, w) lerp(t.Sample(smp, uv), t##2.Sample(smp, uv), (w).x)
#endif
// Layer 1's AO, faded out wherever the other layers take over.
#define BLEND_AO(ao, w) ((ao) + (1.0 - (ao)) * (1.0 - (1.0 - (w).x) * (1.0 - (w).y) * (1.0 - (w).z)))

// All layers' heights at uv and mip lod (absent layers read 0).
float4 BlendHeightsAt(float2 uv, float lod)
{
	float4 h = 0;
	h.x = heightMap.SampleLevel(aoSampler, uv, lod).r;
	h.y = heightMap2.SampleLevel(aoSampler, uv, lod).r;
#if BLEND_LAYERS >= 3
	h.z = heightMap3.SampleLevel(aoSampler, uv, lod).r;
#endif
#if BLEND_LAYERS >= 4
	h.w = heightMap4.SampleLevel(aoSampler, uv, lod).r;
#endif
	return h;
}

#ifdef BLAK_TESS_COMMON_H
// (height, layer 2 weight) for the domain stages: every layer at the displacement coordinate and its matching mip.
float2 BlendHeight(TessSurface s)
{
	float4 h = 0;
	h.x = TessSampleHeight(heightMap, aoSampler, s);
	h.y = TessSampleHeight(heightMap2, aoSampler, s);
#if BLEND_LAYERS >= 3
	h.z = TessSampleHeight(heightMap3, aoSampler, s);
#endif
#if BLEND_LAYERS >= 4
	h.w = TessSampleHeight(heightMap4, aoSampler, s);
#endif
	float height;
	float3 w = BlendWeights(h, BlendSelector(s.Colour.rgb, s.Colour.a), height);
	return float2(height, w.x);
}
#endif

#endif // BLAK_TESS_BLEND_H
