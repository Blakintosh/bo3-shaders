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
#define BLAK_CUBE_SAMPLER			gTrilinearClampSampler
#define BLAK_VOLUME_SAMPLER			gBilinearClampSampler
#define BLAK_PROBE_WORD(c)			gProbeCullResults.Load(int4(c, 0))
#else
cbuffer LightingGlobals : register(b2)
{
	uint blakNumLights				: packoffset(c0.x);
	uint blakNumRefProbes			: packoffset(c0.y);
	float blakGlobalProbeExposure	: packoffset(c19.x);	// sunConstants.globalProbeExposure
	uint4 blakGlobalProbeData[3]	: packoffset(c35);		// globalProbeConstants
	uint blakNumOverrideProbes		: packoffset(c58.x);
}

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
#define BLAK_GLOBAL_EXPOSURE		blakGlobalProbeExposure
#define BLAK_GLOBAL_PROBE(i)		asfloat(blakGlobalProbeData[i])
#define BLAK_OUTPUT_SCALE			relHDRExposure.y
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

// The stock env BRDF for a dielectric of reflectance f0: the fraction of the prefiltered radiance reflected
float Blak_EnvBRDF(float NdotV, float gloss, float f0)
{
	float2 ab = gEnvBRDFGeneric.SampleLevel(BLAK_VOLUME_SAMPLER, float2(NdotV, gloss) * 0.984375 + 0.0078125, 0);
	return lerp(ab.x, ab.y, f0);
}

#endif // BLAK_LIGHTING_INCLUDED
