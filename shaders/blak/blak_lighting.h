#ifndef BLAK_LIGHTING_INCLUDED
#define BLAK_LIGHTING_INCLUDED

/*
	BO3's forward probe lighting (reflection probes + diffuse probe volumes), for custom lit / transparent shaders.

	Reversed from the stock lit_transparent pixel shader: the ToolsGfx bytecode cache (lit.hlsl, ps_main with
	USE_OIT, D3DDisassemble) and the game's forward lit shader (3Dmigoto decompile, same algorithm, game registers).
	Output matches theirs term for term:

	1. The pixel's 64x64 tile and depth slice index a bitmask of visible probes (32 per word). Override probes
	   (the last numOverrideProbes) go first. Regular probes then get the weight they leave.
	2. Per probe: AABB cull, then the attenuation volumes (6 planes each, chained by 2 flag bits: intersect,
	   union or subtract), times the probe's blend weight.
	3. Specular: the reflection ray is box-projected (parallax-corrected) against the probe's 6 planes, rotated
	   into probe space and looked up in the cube array at a lod from gloss and hit distance. Diffuse: the
	   probe's ambient-cube volume (X/Y/Z 3D textures, +/- halves) times the cube's lowest mip. Specular is
	   normalised against the diffuse luminance, as stock does.
	4. Total weight over 1 is normalised; under 0.99 the global probe (cube slice 0 plus the global volume) fills
	   the rest.
	5. Env BRDF (env_brdf_generic): x = reflectance at F0 = 0, y = at F0 = 1.

	Everything is in lighting units. Multiply by BLAK_OUTPUT_SCALE (relHDRExposure.y / invExposure) to get
	the space of the lit HDR target, the same space as resolvedPostSun.

	Game: the linker binds these code resources by name (the game's names: refProbeConstants etc., not the tools'
	gProbes), so only the names matter; the registers follow the stock shaders. The techset must declare
	samplerLinear and samplerLinearClamp as shared samplers:
		samplerLinear = Sampler( "tile both", "mip (1x trilinear)", true )
		samplerLinearClamp = Sampler( "no tile", "mip (1x trilinear)", true )
	Tools (APE / Apex): bound by name, code samplers s12/s13.
	The including shader keeps its own material textures and samplers off these registers.
*/

// 80 B: probe cull box (camera-relative centre, half extents), after numLights light entries
struct BlakCullConstants
{
	float4 centreExtentX;
	float4 extentYZ;
	float4 unused0;
	float4 unused1;
	float4 unused2;
};

// 224 B: one reflection probe (CoreReflectionProbePack). As floats f0..f55:
//  f0-2   origin (camera-relative)         f3-11  world -> probe rotation (rows f3,f4,f5 / f6,f7,f8 / f9,f10,f11)
//  f12-14 1 / volume size                  f15-17 capture point offset (box projection)
//  f18-20 volume uvw scale                 f21-23 volume uvw bias
//  f24    attenuation chain flags (uint)   f25    blend weight
//  f29    intensity                        f30    uint: 0-15 first attenuation volume, 16-24 cube slice, 25-30 count
//  f32-55 6 box-projection planes (xyz normal, w distance)
struct BlakProbePack
{
	uint4 data[14];
};

// 96 B: one attenuation volume (CoreReflectionProbeAttenuationPack): 6 planes, weight = prod saturate(n.p + d)
struct BlakProbeAttenuationPack
{
	float4 planes[6];
};

#if TOOLSGFX
StructuredBuffer<BlakCullConstants> gCullConstants : register(t21);
StructuredBuffer<BlakProbePack> gProbes : register(t23);
StructuredBuffer<BlakProbeAttenuationPack> gReflectionProbeBlends : register(t24);
#define BLAK_PROBES					gProbes
#define BLAK_PROBE_VOLUMES			gReflectionProbeBlends
Texture3D<uint> gProbeCullResults : register(t42);
Texture2D<float2> gEnvBRDFGeneric : register(t44);
Texture3D<float3> gProbeXArray : register(t46);
Texture3D<float3> gProbeYArray : register(t47);
Texture3D<float3> gProbeZArray : register(t48);
TextureCubeArray<float3> gReflectionProbeArray : register(t51);
SamplerState gTrilinearClampSampler : register(s12);
SamplerState gBilinearClampSampler : register(s13);

#define BLAK_NUM_LIGHTS				gScene.numLights
#define BLAK_NUM_PROBES				gScene.numProbes
#define BLAK_NUM_OVERRIDE_PROBES	gScene.numOverrideProbes
#define BLAK_GLOBAL_EXPOSURE		gScene.sun.globalProbeExposure
#define BLAK_GLOBAL_PROBE(i)		asfloat(gScene.globalProbe.data[i])
#define BLAK_OUTPUT_SCALE			gScene.invExposure
#define BLAK_SUN					gScene.sun
#define BlakSSTLightingConstants	SSTLightingConstants

StructuredBuffer<uint> gSunShadowTree : register(t40);
Texture2DArray<float> gSunShadowmapArray : register(t54);
SamplerComparisonState gCmpBilinearClampSampler : register(s15);
#define BLAK_CUBE_SAMPLER			gTrilinearClampSampler
#define BLAK_VOLUME_SAMPLER			gBilinearClampSampler
#define BLAK_PROBE_WORD(c)			gProbeCullResults.Load(int4(c, 0))
#else
// LightingGlobals.sunConstants (the tools' CoreSunConstants)
struct BlakSSTConstants
{
	float2 dimensionInTiles;
	float inchesPerTexel;
	float spanInInches;
};

struct BlakSSTLightingConstants
{
	BlakSSTConstants constants;
	row_major float4x4 offToPinTransform;
	float coordScale;
	uint rootOffset;
	uint2 pad0;
};

struct BlakSunConstants
{
	float3 wldDir;
	float splitDepthOffset;
	float3 color;
	float specScale;
	float globalProbeExposure;
	float3 avgGlobalProbeColor;
	float4 splitPinTransform[3];
	uint sunCookieIndex;
	float sunCookieIntensity;
	float sunVolumetricCookieIntensity;
	uint toolsGfxDisableSunShadow;
	float4 sunCookieTransform[2];
	float intensity;
	int splitArrayOffset;
	float2 pad0;
	BlakSSTLightingConstants sstLightingConstants;
};

cbuffer LightingGlobals : register(b2)
{
	uint blakNumLights				: packoffset(c0.x);
	uint blakNumRefProbes			: packoffset(c0.y);
	BlakSunConstants blakSun		: packoffset(c17);		// sunConstants
	uint4 blakGlobalProbeData[3]	: packoffset(c35);		// globalProbeConstants
	uint blakNumOverrideProbes		: packoffset(c58.x);
	uint blakEnableDitheredShadow	: packoffset(c58.y);
	uint blakViewmodelSunShadowRaw	: packoffset(c53.x);	// the extra player shadow light, +1: viewmodel << 16 | world
}

// 240 B: a light (lightConstants). The extra player shadow reads: f7 (dword 7) low 16 bits = shadow map slice,
// f13 = filter radius (uv), f17-f28 = shadow matrix rows 0-2, f33-f36 = uv scale.xz / bias.yw, f37-f40 = uv scale.xy /
// offset.zw, f41-f42 = depth bias / scale
struct BlakLightPack
{
	uint4 data[15];
};
StructuredBuffer<BlakLightPack> lightConstants : register(t12);
Texture2DArray<float> gSpotShadowmapArray : register(t9);

StructuredBuffer<uint> gSunShadowTree : register(t23);
Texture2DArray<float> gSunShadowmapArray : register(t13);
Texture2DArray<float> gTransShadowmapArray : register(t31);
SamplerComparisonState ShadowSamplerComparisonState : register(s13);

Texture2D<float2> gEnvBRDFGeneric : register(t5);
Texture2DArray<uint> visibleProbes : register(t7);
TextureCubeArray<float3> gReflectionProbeArray : register(t8);
StructuredBuffer<BlakCullConstants> gCullConstants : register(t11);
StructuredBuffer<BlakProbePack> refProbeConstants : register(t15);
StructuredBuffer<BlakProbeAttenuationPack> refProbeAttenuationConstants : register(t16);
#define BLAK_PROBES					refProbeConstants
#define BLAK_PROBE_VOLUMES			refProbeAttenuationConstants
Texture3D<float3> gProbeXArray : register(t17);
Texture3D<float3> gProbeYArray : register(t18);
Texture3D<float3> gProbeZArray : register(t19);
SamplerState samplerLinear : register(s2);
SamplerState samplerLinearClamp : register(s3);

#define BLAK_NUM_LIGHTS				blakNumLights
#define BLAK_NUM_PROBES				blakNumRefProbes
#define BLAK_NUM_OVERRIDE_PROBES	blakNumOverrideProbes
#define BLAK_GLOBAL_EXPOSURE		blakSun.globalProbeExposure
#define BLAK_GLOBAL_PROBE(i)		asfloat(blakGlobalProbeData[i])
#define BLAK_OUTPUT_SCALE			relHDRExposure.y
#define BLAK_SUN					blakSun
#define BLAK_CUBE_SAMPLER			samplerLinear
#define BLAK_VOLUME_SAMPLER			samplerLinearClamp
#define BLAK_PROBE_WORD(c)			visibleProbes.Load(int4(c, 0))
#endif

struct BlakProbeLighting
{
	float3 diffuse;		// irradiance (multiply by albedo)
	float3 specular;	// prefiltered radiance along R (multiply by the env BRDF)
	float weight;		// local probe coverage, 0..1 (the global probe fills 1 - weight)
};

struct BlakProbeSurface
{
	float3 position;	// camera-relative world position
	float3 N;			// shading normal (world)
	float3 R;			// reflection vector (world)
	float gloss;		// 0..1 (stock: gloss map range / 17)
	float NdotV;
	float4 svPosition;	// SV_Position (tile and depth slice)
};

// True when this draw has the probe data bound (APE without lighting, or a pass that binds none, has nothing)
bool Blak_ProbesBound()
{
	uint w, h, elements, mips;
	gReflectionProbeArray.GetDimensions(0, w, h, elements, mips);
	return w != 0;
}

// The probe cull grid cell: 64x64 px tiles, 16 depth slices of 16 words (512 probes)
uint3 Blak_ProbeCell(float4 svPosition)
{
#if TOOLSGFX
	float z = max(svPosition.z, 0.0);
#else
	// the game packs the viewmodel's depth into the top 1/64 of the range
	float z = svPosition.z >= 0.984375 ? svPosition.z * 64.0 - 63.0 : svPosition.z * 1.01587307;
	z = max(z, 9.99999994e-09);
#endif
	uint slice = (uint)min((1.0 / z) * 0.0078125, 15.0);
	return uint3((uint2)svPosition.xy >> 6, slice << 4);
}

float Blak_AttenuationVolume(uint index, float3 rel)
{
	BlakProbeAttenuationPack v = BLAK_PROBE_VOLUMES[index];
	float w = 1.0;
	[unroll]
	for (int i = 0; i < 6; i++)
		w *= saturate(dot(v.planes[i].xyz, rel) + v.planes[i].w);
	return w;
}

// The probe's attenuation chain: volume 0 starts it (flag bit 0: into the intersect term instead), then each further
// volume k uses flag bits 2k (intersect with the running term) and 2k+1 (subtract instead of union)
float Blak_ProbeAttenuation(uint flags, uint packed, float3 rel)
{
	uint first = packed & 0xffff;
	uint count = (packed >> 25) & 63;
	float w0 = Blak_AttenuationVolume(first, rel);
	float2 ab = (flags & 1) ? float2(w0, 0.0) : float2(1.0, w0);
	[loop]
	for (uint k = 1; k < count; k++)
	{
		float x = ab.x * Blak_AttenuationVolume(first + k, rel);
		uint bits = flags >> 2;
		if (bits & 1)
			ab.x = x;
		else
			ab = float2(1.0, (bits & 2) ? ab.y * (1.0 - x) : max(x, ab.y));
		flags = bits;
	}
	return saturate(ab.y);
}

float3 Blak_SampleAmbientVolume(float3 uvw, float3 n, float3 weight)
{
	float3 off = n > 0.0 ? 0.0 : 0.5;		// +axis in the first half of z, -axis in the second
	return gProbeXArray.SampleLevel(BLAK_VOLUME_SAMPLER, uvw + float3(0, 0, off.x), 0) * weight.x
		 + gProbeYArray.SampleLevel(BLAK_VOLUME_SAMPLER, uvw + float3(0, 0, off.y), 0) * weight.y
		 + gProbeZArray.SampleLevel(BLAK_VOLUME_SAMPLER, uvw + float3(0, 0, off.z), 0) * weight.z;
}

float Blak_Luminance(float3 c)
{
	return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// One local probe. weight = blend weight x attenuation (> 0).
void Blak_AccumulateProbe(BlakProbePack p, float weight, float3 rel, BlakProbeSurface s, float specNorm, float minDist,
	inout BlakProbeLighting acc)
{
	float4 d0 = asfloat(p.data[0]);
	float4 d1 = asfloat(p.data[1]);
	float4 d2 = asfloat(p.data[2]);
	float4 d3 = asfloat(p.data[3]);
	float4 d4 = asfloat(p.data[4]);
	float4 d5 = asfloat(p.data[5]);
	float3 row0 = float3(d0.w, d1.z, d2.y);
	float3 row1 = float3(d1.x, d1.w, d2.z);
	float3 row2 = float3(d1.y, d2.x, d2.w);
	float iw = asfloat(p.data[7].y) * weight;
	float slice = (float)((p.data[7].z >> 16) & 511);

	// Box projection: distance along R to the nearest of the probe's planes (never closer than minDist)
	float dist = 131072.0;
	[unroll]
	for (int i = 0; i < 6; i++)
	{
		float4 plane = asfloat(p.data[8 + i]);
		float pd = dot(rel, plane.xyz) - plane.w;
		float s0 = pd >= 0.0 ? max(minDist, abs(pd)) : -max(minDist, abs(pd));
		dist = min(abs(s0 / max(-dot(s.R, plane.xyz), 0.0)), dist);
	}
	float3 hit = rel + float3(d3.w, d4.x, d4.y) + s.R * dist;
	float lod = (1.0 - s.gloss) * 5.0 + sqrt(2.0 * dist / length(hit)) - 0.8448;
	float3 hitL = float3(dot(hit, row0), dot(hit, row1), dot(hit, row2));
	float3 spec = gReflectionProbeArray.SampleLevel(BLAK_CUBE_SAMPLER, float4(hitL, slice), lod) * iw;

	float3 relL = float3(dot(rel, row0), dot(rel, row1), dot(rel, row2));
	float3 uvw = saturate(relL * d3.xyz + 0.5) * float3(d4.z, d4.w, d5.x) + d5.yzw;
	float3 nL = float3(dot(s.N, row0), dot(s.N, row1), dot(s.N, row2));
	float3 irr = Blak_SampleAmbientVolume(uvw, nL, nL * nL * iw);
	float3 diff = irr * gReflectionProbeArray.SampleLevel(BLAK_CUBE_SAMPLER, float4(nL, slice), 6.0);

	acc.diffuse += diff;
	float lumD = specNorm * Blak_Luminance(diff);
	acc.specular += spec * (lumD / (lumD + Blak_Luminance(spec)));
}

// Probes [begin, end) of the visible-probe bitmask. overrideWeight > 0 for the regular probes: they get what the
// override probes left.
void Blak_ProbeRange(uint begin, uint end, float overrideWeight, bool regular, uint3 cell, BlakProbeSurface s,
	float specNorm, float minDist, inout BlakProbeLighting acc)
{
	uint lowMaskBits = begin & 31;	// the first word's probes below begin belong to the other range
	uint highBits = end & 31;
	uint firstWord = begin & ~31u;
	uint lastWord = end & ~31u;
	[loop]
	for (uint base = firstWord; base < end; base += 32)
	{
		uint word = BLAK_PROBE_WORD(cell + uint3(0, 0, base >> 5));
		if (base == firstWord && lowMaskBits != 0)
			word &= ~((1u << lowMaskBits) - 1u);
		if (base == lastWord)
			word &= highBits == 0 ? 0u : (0xffffffffu >> (32 - highBits));
		[loop]
		while (word != 0)
		{
			uint bit = firstbitlow(word);
			word ^= 1u << bit;
			uint index = base + bit;

			BlakCullConstants box = gCullConstants[BLAK_NUM_LIGHTS + index];
			float3 d = abs(box.centreExtentX.xyz - s.position);
			if (!(d.x < box.centreExtentX.w && d.y < box.extentYZ.x && d.z < box.extentYZ.y))
				continue;

			BlakProbePack p = BLAK_PROBES[index];
			float3 rel = s.position - asfloat(p.data[0].xyz);
			float b = Blak_ProbeAttenuation(p.data[6].x, p.data[7].z, rel);
			if (regular)
				b = saturate(b - overrideWeight);
			float weight = asfloat(p.data[6].y) * b;
			if (weight > 0.0)
			{
				acc.weight += weight;
				Blak_AccumulateProbe(p, weight, rel, s, specNorm, minDist, acc);
			}
		}
	}
}

BlakProbeLighting Blak_ProbeLighting(BlakProbeSurface s)
{
	BlakProbeLighting acc = (BlakProbeLighting)0;
	float r = 1.0 - s.gloss;

	// The specular / diffuse luminance ratio a probe's specular may reach (stock fit, grows with gloss and NdotV)
	float specNorm = max(max(exp2(6.85741 - 10.0 * r) * s.NdotV * 9.13681,
		exp2(7.085 - 5.0 * r - 2.015905 * 5.0 * r * r) * s.NdotV * 9.70809), 1.26816);
	float minDist = 100.0 * max(0.0, (5.0 * r - 2.5) * 0.4);

	uint numProbes = BLAK_NUM_PROBES;
	uint numRegular = numProbes - BLAK_NUM_OVERRIDE_PROBES;
	uint3 cell = Blak_ProbeCell(s.svPosition);

	Blak_ProbeRange(numRegular, numProbes, 0.0, false, cell, s, specNorm, minDist, acc);
	if (acc.weight < 1.0)
		Blak_ProbeRange(0, numRegular, acc.weight, true, cell, s, specNorm, minDist, acc);

	float norm = 1.0 / max(acc.weight, 1.0);
	acc.diffuse *= norm;
	acc.specular *= norm;
	acc.weight = saturate(acc.weight);

	// The global probe fills what the local probes left
	if (acc.weight < 0.99)
	{
		float ge = BLAK_GLOBAL_EXPOSURE * (1.0 - acc.weight);
		float4 g0 = BLAK_GLOBAL_PROBE(0);
		float4 g1 = BLAK_GLOBAL_PROBE(1);
		float4 g2 = BLAK_GLOBAL_PROBE(2);
		float3 t = saturate((s.position - g0.xyz) * float3(g0.w, g1.xy) + 0.5);
		float3 uvw = t * float3(g1.zw, g2.x) + g2.yzw;
		float3 amb = Blak_SampleAmbientVolume(uvw, s.N, s.N * s.N * ge);
		float3 diff = amb * gReflectionProbeArray.SampleLevel(BLAK_CUBE_SAMPLER, float4(s.N, 0), 6.0);
		acc.diffuse += diff;
		float lumG = Blak_Luminance(diff);
		float3 spec = gReflectionProbeArray.SampleLevel(BLAK_CUBE_SAMPLER, float4(s.R, 0), r * 5.0);
		acc.specular += spec * lerp(lumG, ge, s.gloss);
	}
	return acc;
}

// The stock gloss filter: a BO3 normal map keeps its mip-filtered variance in blue (scaled like the normal, by
// baseNormalHeight), and the lit shaders widen the lobe by it before any lighting
float Blak_ToksvigGloss(float gloss, float variance)
{
	float v = min(variance * variance * 0.333333, 1.0);
	return max(-log2(exp2(-17.0 * saturate(gloss)) + v) * 0.0588235, 0.0);
}

// ---- Sun shadow: the stock lit shaders' lookup ----
// The position goes into "pin" space (the sun's view). Within the three cascades it is a comparison lookup of the
// cascade shadow maps (in the game also the translucent-shadow map, and an 8-tap dithered blend into the next cascade
// when dithered shadows are on); beyond them it is the static sun shadow tree (SST): a quadtree of occluder heights,
// lit when the occluder height is not below the point (less two texels).

// Occluder height at a pin-space xy, from the SST
float Blak_SSTHeight(float3 pin)
{
	BlakSSTLightingConstants sst = BLAK_SUN.sstLightingConstants;
	float tileScale = 1.0 / (128.0 * sst.constants.inchesPerTexel);
	float3 c = float3(pin.x * tileScale + 0.5 * sst.constants.dimensionInTiles.x, -pin.y * tileScale + 0.5 * sst.constants.dimensionInTiles.y,
		pin.x * tileScale + 0.5 * sst.constants.dimensionInTiles.x);
	c = min(max(c, 0.0), sst.constants.dimensionInTiles.xyx - 0.0078125);
	float2 cell = floor(c.zy * sst.coordScale);
	uint index = (uint)(cell.y * sst.constants.dimensionInTiles.x * sst.coordScale + cell.x) + sst.rootOffset;
	uint node = gSunShadowTree[index];
	if (node & 0x40000000)
		return asfloat(node << 2);									// the whole tile at one height

	// Texel within the tile, 0..127 (x twice: the 2D descent reads .zy, the leaf reads .x)
	uint base = index + (node & 0x01ffffff);
	uint3 t = (uint3)(frac(c * (float)(node >> 25)) * 128.0);

	// Up to two levels of 2x2 nodes with 13-bit child offsets
	uint n0 = gSunShadowTree[base];
	uint stop0 = n0 & 0xc0000000;
	uint pick = (t.y >> 6) ? n0 : gSunShadowTree[base + 1];
	pick = ((t.z >> 6) ? (pick >> 13) : pick) & 8191;
	uint i1 = pick + base;
	uint n1 = gSunShadowTree[i1];
	uint3 cur = stop0 ? uint3(base, 0, n0) : uint3(i1, 1, n1);		// (index, level, node)
	uint shift = stop0 ? 6 : 5;
	uint2 bits = (t.zy >> shift) & 1;
	uint stop1 = cur.z & 0xc0000000;
	pick = bits.y ? cur.z : gSunShadowTree[cur.x + 1];
	pick = (bits.x ? (pick >> 13) : pick) & 8191;
	uint i2 = pick + cur.x;
	uint n2 = gSunShadowTree[i2];
	cur = stop1 ? cur : uint3(i2, cur.y + 1, n2);
	cur = stop0 ? uint3(base, 0, n0) : cur;

	// Up to three levels of 4-way nodes with 10-bit child offsets
	if ((cur.z & 0xc0000000) == 0)
	{
		uint2 q = t.zy >> (6 - cur.y);
		uint o = ((cur.z | 0x40000000) >> ((((q.y & 1) << 1) | (q.x & 1)) * 10)) & 1023;
		uint ia = o + cur.x;
		uint na = gSunShadowTree[ia];
		uint stopA = na & 0xc0000000;

		q = t.zy >> (6 - (cur.y + 1));
		o = ((na | 0x40000000) >> ((((q.y & 1) << 1) | (q.x & 1)) * 10)) & 1023;
		uint ib = o + ia;
		uint nb = gSunShadowTree[ib];
		uint3 b3 = stopA ? uint3(ia, cur.y + 1, na) : uint3(ib, cur.y + 2, nb);

		q = t.zy >> (6 - b3.y);
		uint stopB = b3.z & 0xc0000000;
		o = ((b3.z | 0x40000000) >> ((((q.y & 1) << 1) | (q.x & 1)) * 10)) & 1023;
		uint ic = o + b3.x;
		uint nc = gSunShadowTree[ic];
		uint2 r = stopB ? uint2(b3.x, b3.z) : uint2(ic, nc);
		cur.xz = stopA ? uint2(ia, na) : r;
	}

	if ((cur.z & 0xc0000000) == 0)
	{
		// Height texels: 8-bit or 16-bit, over [base, base + range]
		float lo = (float)((cur.z >> 15) & 0x3fff) * sst.constants.spanInInches * 6.10351563e-05;
		float range = (float)(cur.z & 0x7fff) * sst.constants.spanInInches * 3.05185094e-05;
		uint w8 = gSunShadowTree[(t.y & 3) + cur.x + 1];
		float h8 = (float)((w8 >> ((t.x & 3) << 3)) & 255) * range * 0.00392156886 + lo;
		uint w16 = gSunShadowTree[((t.y & 3) << 1) + 1 + ((t.z >> 1) & 1) + cur.x];
		float h16 = (float)((w16 >> ((t.z & 1) << 4)) & 0xffff) * range * 1.52590219e-05 + lo;
		return (cur.z & 0x20000000) ? h8 : h16;
	}
	// A plane: height + slopes (half floats) in x and y
	uint slopes = (cur.z & 0x80000000) ? gSunShadowTree[cur.x + 1] : 0;
	return asfloat(cur.z << 2) + pin.x * f16tof32(slopes >> 16) + pin.y * f16tof32(slopes & 0xffff);
}

// Sun visibility, 0..1, at a camera-relative position
float Blak_SunShadow(float3 position, float2 pixel)
{
#if TOOLSGFX
	if (BLAK_SUN.toolsGfxDisableSunShadow == 1)
		return 1.0;
#endif
	float3 pin = mul(float4(position, 1.0), BLAK_SUN.sstLightingConstants.offToPinTransform).xyz;
	float depth = 1.0 - (pin.z - BLAK_SUN.splitDepthOffset) * 6.10351563e-05;

	uint split = 3;
	float edge = 0.0;
	if (depth == saturate(depth))
	{
		[unroll]
		for (uint i = 0; i < 3; i++)
		{
			float2 d = (pin.xy - BLAK_SUN.splitPinTransform[i].xy) * BLAK_SUN.splitPinTransform[i].z;
			edge = max(abs(d.x), abs(d.y));
			if (edge < 1.0)
			{
				split = i;
				break;
			}
		}
	}

	if (split >= 3)
		return Blak_SSTHeight(pin) < pin.z - 2.0 * BLAK_SUN.sstLightingConstants.constants.inchesPerTexel ? 0.0 : 1.0;

	float2 uv = (pin.xy - BLAK_SUN.splitPinTransform[split].xy) * BLAK_SUN.splitPinTransform[split].z * float2(0.5, -0.5) + 0.5;
#if TOOLSGFX
	return gSunShadowmapArray.SampleCmpLevelZero(gCmpBilinearClampSampler, float3(uv, BLAK_SUN.splitArrayOffset + split), depth);
#else
	if (blakEnableDitheredShadow == 0)
	{
		float3 c = float3(uv, BLAK_SUN.splitArrayOffset + split);
		float v = saturate(gSunShadowmapArray.SampleCmpLevelZero(ShadowSamplerComparisonState, c, depth)
			+ gTransShadowmapArray.SampleLevel(samplerLinearClamp, c, 0) - 1.0);
		return v * v * v;
	}

	// Dithered: 8 rotated taps, blending into the next cascade near this one's edge
	static const float2 taps[8] = { float2(-0.808114, 0.808114), float2(0, -1), float2(0.606057, 0.606057), float2(-0.714286, 0),
		float2(0.404114, -0.404114), float2(0, 0.428571), float2(-0.202057, -0.202057), float2(0.142857, 0) };
	float angle = frac(52.9829189 * frac(dot((float2)(uint2)pixel, float2(0.0671105608, 0.00583714992)))) * 6.28318548 + gameTick.w;
	float sn, cs;
	sincos(angle, sn, cs);
	uint next = min(split + 1, 2);
	uint blendFrom = (uint)(28.0 * (1.0 - edge));
	float2 uvNext = (pin.xy - BLAK_SUN.splitPinTransform[next].xy) * BLAK_SUN.splitPinTransform[next].z * float2(0.5, -0.5) + 0.5;
	float sum = 0.0;
	[unroll]
	for (uint k = 0; k < 8; k++)
	{
		bool useNext = blendFrom < k;
		uint sp = useNext ? next : split;
		float2 o = float2(dot(taps[k].yx, float2(-sn, cs)), dot(taps[k].yx, float2(cs, sn)));
		float3 c = float3(o * BLAK_SUN.splitPinTransform[sp].w + (useNext ? uvNext : uv), BLAK_SUN.splitArrayOffset + sp);
		sum += saturate(gSunShadowmapArray.SampleCmpLevelZero(ShadowSamplerComparisonState, c, depth)
			+ gTransShadowmapArray.SampleLevel(samplerLinearClamp, c, 0) - 1.0) * 0.125;
	}
	return sum * sum * sum;
#endif
}

#if !TOOLSGFX
static const float2 blakShadowTaps[8] = { float2(-0.808114, 0.808114), float2(0, -1), float2(0.606057, 0.606057), float2(-0.714286, 0),
	float2(0.404114, -0.404114), float2(0, 0.428571), float2(-0.202057, -0.202057), float2(0.142857, 0) };

// The stock extra shadow on the sun around the player: a projected shadow map from a dedicated light, one for the
// viewmodel (isDepthHack draws) and one for the world, chosen by viewmodelSunShadowRaw. 1 outside its map.
float Blak_PlayerSunShadow(float3 position, float3 N, float NdotLRaw, float2 pixel)
{
	uint light = isDepthHack != 0 ? (blakViewmodelSunShadowRaw >> 16) : (blakViewmodelSunShadowRaw & 0xffff);
	if (light == 0)
		return 1.0;
	BlakLightPack l = lightConstants[light + BLAK_NUM_LIGHTS - 1];
	float radius = asfloat(l.data[3].y);
	float4 row0 = float4(asfloat(l.data[4].y), asfloat(l.data[4].z), asfloat(l.data[4].w), asfloat(l.data[5].x));
	float4 row1 = float4(asfloat(l.data[5].y), asfloat(l.data[5].z), asfloat(l.data[5].w), asfloat(l.data[6].x));
	float4 row2 = float4(asfloat(l.data[6].y), asfloat(l.data[6].z), asfloat(l.data[6].w), asfloat(l.data[7].x));
	float4 uvMap = float4(asfloat(l.data[8].y), asfloat(l.data[8].z), asfloat(l.data[8].w), asfloat(l.data[9].x));
	float4 uvAtlas = float4(asfloat(l.data[9].y), asfloat(l.data[9].z), asfloat(l.data[9].w), asfloat(l.data[10].x));
	float2 depthMap = float2(asfloat(l.data[10].y), asfloat(l.data[10].z));

	float4 p = float4(position + N * (0.4 - 0.2 * abs(NdotLRaw)), 1.0);
	float2 uv = float2(dot(row0, p), dot(row1, p)) * float2(0.5, -0.5) + 0.5;
	uv = (uv + uvAtlas.zw) * uvAtlas.xy;
	float2 margin = radius / uvMap.xz;
	if (any(uv >= 1.0 - margin) || any(margin >= uv))
		return 1.0;
	float slice = (float)(l.data[1].w & 0xffff);
	float2 tc = saturate(uv) * uvMap.xz + uvMap.yw;
	float depth = max(6.10351563e-05, (dot(row2, p) + depthMap.x) / depthMap.y);
	float v;
	if (blakEnableDitheredShadow != 0)
	{
		float angle = frac(52.9829189 * frac(dot((float2)(uint2)pixel, float2(0.0671105608, 0.00583714992)))) * 6.28318548 + gameTick.w;
		float sn, cs;
		sincos(angle, sn, cs);
		v = 0.0;
		[unroll]
		for (uint k = 0; k < 8; k++)
		{
			float2 o = float2(dot(blakShadowTaps[k].yx, float2(-sn, cs)), dot(blakShadowTaps[k].yx, float2(cs, sn)));
			v += gSpotShadowmapArray.SampleCmpLevelZero(ShadowSamplerComparisonState, float3(o * radius + tc, slice), depth) * 0.125;
		}
	}
	else
		v = gSpotShadowmapArray.SampleCmpLevelZero(ShadowSamplerComparisonState, float3(tc, slice), depth);
	return v * v * v;
}
#endif

struct BlakSunLighting
{
	float3 diffuse;		// multiply by albedo
	float3 specular;	// already weighted by Fresnel for f0
};

// The sun, as the stock lit shaders light a surface with it (before its shadow: multiply both terms by it).
// Specular: GGX with m^2 = 2 / (2 + 2^(17 gloss)), Smith-Schlick visibility, Schlick Fresnel, x sun.specScale.
BlakSunLighting Blak_SunLighting(float3 N, float3 V, float gloss, float f0)
{
	BlakSunLighting sun = (BlakSunLighting)0;
	float3 L = BLAK_SUN.wldDir;
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0)
		return sun;
	float NdotV = saturate(dot(N, V));
	float m2 = 2.0 / (2.0 + exp2(17.0 * gloss));
	float a = sqrt(m2);
	float k = (sqrt(a) * 0.5 + 0.5);
	k = k * k * 0.5;
	float g1v = NdotV * (1.0 - k) + k;
	float g1l = NdotL * (1.0 - k) + k;
	float3 H = normalize(V + L);
	float NdotH = abs(dot(N, H));
	float d = NdotH * NdotH * (m2 - 1.0) + 1.0;
	float spec = m2 * BLAK_SUN.specScale * NdotL * 0.25 / (g1v * g1l * d * d);
	float fc = saturate(1.0 - dot(H, V));
	fc = fc * fc * fc * fc * fc;
	sun.specular = BLAK_SUN.color * spec * (f0 + (1.0 - f0) * fc);

	// Diffuse: N.L, softened at grazing for rough surfaces
	float w = 1.0 - NdotL * (1.0 - NdotV * 0.5);
	w = 0.62 - w * w * 0.62;
	sun.diffuse = BLAK_SUN.color * lerp(NdotL, w, a);
	return sun;
}

// The stock env BRDF for a dielectric of reflectance f0: the fraction of the prefiltered radiance reflected
float Blak_EnvBRDF(float NdotV, float gloss, float f0)
{
	float2 ab = gEnvBRDFGeneric.SampleLevel(BLAK_VOLUME_SAMPLER, float2(NdotV, gloss) * 0.984375 + 0.0078125, 0);
	return lerp(ab.x, ab.y, f0);
}

#endif // BLAK_LIGHTING_INCLUDED
