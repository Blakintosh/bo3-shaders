#define PC

#include "Include/Common.hlsl"

/*
    Frosted Glass - translucent glass / polymer in ONE draw: viewmodel parts (see-through mags), world windows,
    anything with a normal map. One source for the game (shaders_stable) and the tools (shaders_stable_toolsgfx).

    MW2019/MWII draw a translucent mag as one lit-transparent material: albedo (dirt), normal + gloss (smudges live
    in the gloss), a transmission colour map (_tr) and a thickness map (_th). The renderer samples a resolved copy
    of the scene, blurrier where the surface is rougher / thicker. The old BO3 ports split that into a
    lit_transparent_plus shell plus a blak_glass_blur / 3d_scene_blur shell; this does both:

    1. Transmission: the resolved scene is sampled through the refracted ray (the normal map bends it, projected
       with this draw's own view-projection so it holds for the viewmodel FOV and for world glass at any distance),
       blurred with a rotated Vogel disc whose radius is blurRadius x thickness x roughness, tinted by the
       transmission map x tint and darkened by thickness (absorption).
    2. Surface: Schlick Fresnel, a glossy "environment" reflection taken from the scene itself along the reflected
       direction, a GGX highlight from a camera-relative key light scaled by the local scene brightness, and the
       albedo (dirt / print) lit by the same local ambient. BO3's forward light data is not reachable from a custom
       shader, so (2) is built from the screen: it follows the scene's exposure and colour, not true probe lighting.

    Game: "blend" with depth test, no depth write, emissive + current resolve render flags (resolvedPostSun).
    Tools (APE / Apex): drawn as a transparent through the "oit" technique, which appends a premultiplied fragment
    to the per-pixel OIT list (the fallback target only when the list is full), like the stock OIT shaders. Apex
    binds a mipped copy of the opaque lit scene to iResolveScene there; APE binds nothing, so in APE every term
    built from the scene is black.
*/

#if TOOLSGFX
#define cameraSide			gScene.transforms.camToWldMatrix[0]
#define cameraUp			gScene.transforms.camToWldMatrix[1]
#define cameraLook			gScene.transforms.camToWldMatrix[2]
#define targetSize			float2(gScene.renderTargetSize)
#else
#define targetSize			renderTargetSize
#endif

struct VertexShaderInput
{
	float3 				Position    				: POSITION;
	float4 				Colour      				: COLOR;
	float2 				TexCoord    				: TEXCOORD;
	float3 				Normal      				: NORMAL;
	float4 				Tangent     				: TANGENT;
	float4              Weights                     : BLENDWEIGHT;
	uint4               Indices                     : BLENDINDICES;
};

struct VertexShaderOutput
{
	float4 				Position    				: SV_POSITION;
	float2 				TexCoord    				: TEXCOORD0;
	float3 				Normal      				: TEXCOORD1;
	float3 				Tangent     				: TEXCOORD2;
	float3 				BiTangent   				: TEXCOORD3;
	float3 				CameraPos   				: TEXCOORD4;	// position relative to the eye (world axes)
#if GENERATE_MOTION_VECTOR
	float4 				MotionVectorPosition 		: TEXCOORD7;
#endif
};

// Code range (t18+): bound by the frame code, never by the material
Texture2D<float4> iResolveScene : register(t49);
#if TOOLSGFX
// ToolsGfx binds material textures and samplers by name but rejects a material whose slots are not contiguous from
// t0 / s0 (APE Material_ResolveTextures / Material_ResolveSamplerStates)
SamplerState materialSampler : register(s0);
SamplerState sceneSampler : register(s1);
Texture2D<float4> normalMap : register(t0);
Texture2D<float4> glossMap : register(t1);
Texture2D<float4> colorMap : register(t2);
Texture2D<float4> transmissionMap : register(t3);
Texture2D<float4> thicknessMap : register(t4);
#else
SamplerState materialSampler : register(s3);
SamplerState sceneSampler : register(s4);
Texture2D<float4> normalMap : register(t1);
Texture2D<float4> glossMap : register(t2);
Texture2D<float4> colorMap : register(t3);
Texture2D<float4> transmissionMap : register(t4);
Texture2D<float4> thicknessMap : register(t5);
#endif

#if USE_OIT
// ToolsGfx OIT (resolved by oit_compute.hlsl): each pixel keeps a list of up to 9 fragments, sorted by depth and
// composited back to front over (scene x fallback.a + fallback.rgb). The resolve copies the scene untouched where
// the list is empty, so the fallback target alone shows nothing: a draw appends itself to the list and writes
// the fallback only when the list is full, exactly like the stock OIT shaders (lit_glass etc.).
RWTexture2D<uint> gOITFragmentCount : register(u6);
RWTexture2DArray<uint2> gOITFragmentData : register(u7);
#define OIT_MAX_FRAGMENTS	9

// The stock packing: x = the colour's shared exponent (bits 24-31) + 8 mantissa bits per channel, y = the depth's
// bits << 2 (sort key) with alpha * 2046 in bits 1-10. The colour is premultiplied.
uint2 OIT_PackFragment(float3 premulColour, float alpha, float depth)
{
	uint e = (asuint(abs(max(max(premulColour.r, premulColour.g), premulColour.b))) & 0x7f800000) + 0x00800000;
	uint3 m = asuint(asfloat(e) + premulColour);
	uint rgb = ((m.r >> 15) & 0xff) | (((m.g >> 15) & 0xff) << 8) | (((m.b >> 15) & 0xff) << 16);
	uint a = (uint)(saturate(alpha) * 2046.0) & 2046;
	return uint2((e << 1) + rgb, ((asuint(depth) << 2) & ~0x7ffu) | a);
}
#endif

// Material constants: each a techset float1 (one editable field) of the same name; glassTint is the Color
float blurRadius;		// cg01_x Blur Radius (px at 1080p, 0 = clear)
float thicknessToBlur;	// cg01_y Thickness Map -> Blur
float roughnessToBlur;	// cg01_z Roughness -> Blur
float refractionDepth;	// cg01_w Refraction Depth (units behind the surface)
float fresnelF0;			// cg02_x Fresnel F0 (0.04 glass / polymer)
float reflectionStrength;	// cg02_y Reflection Strength
float keyLight;			// cg02_z Highlight Strength
float albedoStrength;	// cg02_w Dirt / Print Strength (Color Map)
float glossMin;			// cg03_x Gloss Min (Gloss Map black)
float glossMax;			// cg03_y Gloss Max (Gloss Map white)
float absorption;		// cg03_z Absorption (darkens with thickness)
float debugView;			// cg03_w Debug View (0 off, 1 thickness, 2 roughness, 3 transmission, 4 normal, 5 fresnel, 6 raw scene, 7 blurred scene)
float opacity;			// cg04_x Opacity
float reflectionOffset;	// cg04_y Reflection Offset
float keyLightSize;		// cg04_z Highlight Size
float normalStrength;	// cg04_w Normal Strength
float3 glassTint;		// colorTint3 Transmission Tint (linear)

// Hot-reload tuning: /D OVR_<name>=<value> overrides a material constant
#ifdef OVR_blurRadius
#undef blurRadius
#define blurRadius OVR_blurRadius
#endif
#ifdef OVR_thicknessToBlur
#undef thicknessToBlur
#define thicknessToBlur OVR_thicknessToBlur
#endif
#ifdef OVR_roughnessToBlur
#undef roughnessToBlur
#define roughnessToBlur OVR_roughnessToBlur
#endif
#ifdef OVR_refractionDepth
#undef refractionDepth
#define refractionDepth OVR_refractionDepth
#endif
#ifdef OVR_fresnelF0
#undef fresnelF0
#define fresnelF0 OVR_fresnelF0
#endif
#ifdef OVR_reflectionStrength
#undef reflectionStrength
#define reflectionStrength OVR_reflectionStrength
#endif
#ifdef OVR_keyLight
#undef keyLight
#define keyLight OVR_keyLight
#endif
#ifdef OVR_albedoStrength
#undef albedoStrength
#define albedoStrength OVR_albedoStrength
#endif
#ifdef OVR_glossMin
#undef glossMin
#define glossMin OVR_glossMin
#endif
#ifdef OVR_glossMax
#undef glossMax
#define glossMax OVR_glossMax
#endif
#ifdef OVR_absorption
#undef absorption
#define absorption OVR_absorption
#endif
#ifdef OVR_debugView
#undef debugView
#define debugView OVR_debugView
#endif
#ifdef OVR_opacity
#undef opacity
#define opacity OVR_opacity
#endif
#ifdef OVR_reflectionOffset
#undef reflectionOffset
#define reflectionOffset OVR_reflectionOffset
#endif
#ifdef OVR_keyLightSize
#undef keyLightSize
#define keyLightSize OVR_keyLightSize
#endif
#ifdef OVR_normalStrength
#undef normalStrength
#define normalStrength OVR_normalStrength
#endif

#define BLUR_TAPS			24
#define ENV_TAPS			8
#define GOLDEN_ANGLE		2.39996323
#define GLASS_ETA			0.6667		// air -> glass / polymer (IOR 1.5)

VertexShaderOutput vs_main(in VertexShaderInput IN, in uint instance : INSTANCE_SEMANTIC)
{
	VertexShaderOutput OUT = (VertexShaderOutput)0;

	float3 pos = IN.Position;
	float3 nor = Utility_DecodeNormal(IN.Normal);
	float3 tan = Utility_DecodeNormal(IN.Tangent.xyz);

	// World vertices (wc/, USE_GPU_SKIN 0) have no bone weights; skinning them would turn them into NaNs
#if USE_GPU_SKIN
	Utility_SkinVertex(pos, nor, tan, IN.Indices, IN.Weights, instance);
#endif

	float3 camPos = Transform_ObjectToCamera(Transform_ObjectPositionToWorldSpace(pos, instance), instance);

	OUT.Position	= Transform_ObjectToClip(camPos, instance);
	OUT.TexCoord	= IN.TexCoord;
	OUT.Normal		= Transform_ObjectNormalToWorldSpace(nor, instance).xyz;
	OUT.Tangent		= Transform_ObjectNormalToWorldSpace(tan, instance).xyz;
	OUT.BiTangent	= cross(OUT.Normal, OUT.Tangent) * Utility_DecodeBiTangentSign(IN.Tangent.w);
	OUT.CameraPos	= camPos;

#if GENERATE_MOTION_VECTOR
	pos = IN.Position;
#if USE_GPU_SKIN
	Utility_SkinVertexMotionVector(pos, IN.Indices, IN.Weights, instance);
#endif
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(Transform_ObjectPositionToWorldSpaceMotionVector(pos, instance));
#endif

	return OUT;
}

float Luminance(float3 c)
{
	return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Per-pixel rotation so the taps read as fine grain instead of rings
float InterleavedGradientNoise(float2 p)
{
	return frac(52.9829189 * frac(dot(p, float2(0.06711056, 0.00583715))));
}

float2 ClampUV(float2 uv, float2 pixel)
{
	return clamp(uv, pixel * 0.5, 1.0 - pixel * 0.5);
}

// Screen UV of a camera-relative position, through the same view-projection as this draw
float2 CameraToScreenUV(float3 camPos)
{
	float4 clip = Transform_ObjectToClip(camPos, 0);
	return clip.xy / max(clip.w, 1e-4) * float2(0.5, -0.5) + 0.5;
}

// Vogel-disc blur of the resolved scene: radius in UV units (x already aspect corrected). When the scene texture
// has mips, each tap reads the level matching the tap spacing, so large radii stay smooth instead of grainy.
float3 BlurScene(float2 uv, float2 radius, float2 pixel, float rotation, int taps, float mipCount)
{
	float spacing = radius.y / (pixel.y * sqrt((float)taps));		// pixels between neighbouring taps
	float lod = clamp(log2(max(spacing, 1.0)), 0.0, mipCount - 1.0);

	// Karis-weighted (1 / (1 + luma)) so single HDR hot pixels (muzzle flash, sparks) don't turn into speckles
	float3 c0 = iResolveScene.SampleLevel(sceneSampler, ClampUV(uv, pixel), lod).rgb;
	float w0 = 1.0 / (1.0 + Luminance(c0));
	float3 sum = c0 * w0;
	float weight = w0;
	[loop]
	for (int i = 0; i < taps; i++)
	{
		float t = (i + 0.5) / taps;
		float r = sqrt(t);
		float a = i * GOLDEN_ANGLE + rotation;
		float2 offset = float2(cos(a), sin(a)) * r * radius;
		float3 c = iResolveScene.SampleLevel(sceneSampler, ClampUV(uv + offset, pixel), lod).rgb;
		// soft gaussian-ish falloff so the edge of the disc does not ring
		float w = exp(-2.0 * t) / (1.0 + Luminance(c));
		sum += c * w;
		weight += w;
	}
	return sum / weight;
}

#if USE_OIT
// Depth test before the shader, so a hidden fragment is never appended to the list
[earlydepthstencil]
#endif
float4 ps_main(in VertexShaderOutput IN, in bool isFrontFace : SV_IsFrontFace) : SV_TARGET0
{
	float2 pixel = 1.0 / targetSize.xy;
	float2 uv = IN.Position.xy * pixel;
	float aspect = targetSize.y * pixel.x;			// height / width
	float pixelScale = targetSize.y / 1080.0;		// blur radius is authored at 1080p
	float rotation = InterleavedGradientNoise(IN.Position.xy) * 6.28318530718;

	uint sceneW, sceneH, sceneMips;
	iResolveScene.GetDimensions(0, sceneW, sceneH, sceneMips);
	float mipCount = max((float)sceneMips, 1.0);

	// -- Surface frame --
	float faceSign = isFrontFace ? 1.0 : -1.0;
	float3 geoNormal = normalize(IN.Normal) * faceSign;
	float3 tangent = normalize(IN.Tangent) * faceSign;
	float3 bitangent = normalize(IN.BiTangent) * faceSign;

	float2 nxy = normalMap.Sample(materialSampler, IN.TexCoord).xy * 1.9921875 - 1.0;
	nxy *= normalStrength;
	float nz = sqrt(saturate(1.0 - dot(nxy, nxy)));
	float3 N = normalize(tangent * nxy.x + bitangent * nxy.y + geoNormal * nz);
	float3 V = normalize(-IN.CameraPos);
	float NdotV = saturate(dot(N, V));

	float gloss = lerp(glossMin, glossMax, glossMap.Sample(materialSampler, IN.TexCoord).x);
	float roughness = saturate(1.0 - gloss);
	float thickness = thicknessMap.Sample(materialSampler, IN.TexCoord).x;
	float3 transmission = transmissionMap.Sample(materialSampler, IN.TexCoord).rgb * glassTint;
	float3 albedo = colorMap.Sample(materialSampler, IN.TexCoord).rgb;

	// -- Refraction: the ray through the bumped surface vs the ray through the flat one, carried refractionDepth
	// units behind the surface and projected. Same for viewmodel and world, and it shrinks with distance. --
	float3 bend = refract(-V, N, GLASS_ETA) - refract(-V, geoNormal, GLASS_ETA);
	float2 sceneUV = uv + (CameraToScreenUV(IN.CameraPos + bend * refractionDepth) - CameraToScreenUV(IN.CameraPos));

	// -- Transmission: refracted, blurred, tinted scene behind --
	float blurAmount = lerp(1.0, thickness, thicknessToBlur) * lerp(1.0, roughness, roughnessToBlur);
	float2 blurUV = float2(aspect, 1.0) * (blurRadius * blurAmount * pixelScale * pixel.y);
	float3 behind = BlurScene(sceneUV, blurUV, pixel, rotation, BLUR_TAPS, mipCount);
	float3 absorb = exp(-absorption * thickness * (1.0 - transmission));
	behind *= transmission * absorb;

	// -- Environment: the scene around the part, wide and blurred, along the reflected direction --
	float3 R = reflect(-V, N);
	float2 reflectUV = uv + float2(dot(R, cameraSide.xyz) * aspect, -dot(R, cameraUp.xyz)) * reflectionOffset;
	float envRadius = lerp(0.04, 0.18, roughness);
	float3 env = BlurScene(reflectUV, float2(aspect, 1.0) * envRadius, pixel, rotation, ENV_TAPS, mipCount);
	float3 ambient = BlurScene(uv, float2(aspect, 1.0) * 0.2, pixel, rotation, ENV_TAPS, mipCount);

	// No scene bound (APE's preview): light the glass from a mid grey instead of drawing it black
	if (sceneW == 0)
	{
		ambient = env = 0.18;
		behind = 0.18 * transmission * absorb;
	}

	// -- Fresnel (Schlick, roughness-damped at grazing) --
	float fresnel = fresnelF0 + (max(1.0 - roughness, fresnelF0) - fresnelF0) * pow(1.0 - NdotV, 5.0);

	// -- Key light: GGX highlight from above and behind the camera, scaled by the local scene brightness --
	float3 L = normalize(cameraUp.xyz * 0.75 - cameraLook.xyz * 0.45 + cameraSide.xyz * 0.3);
	float3 H = normalize(L + V);
	float NdotL = saturate(dot(N, L));
	float NdotH = saturate(dot(N, H));
	float a = max(roughness * roughness, keyLightSize * 0.05 + 0.002);
	float a2 = a * a;
	float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
	float D = a2 / (3.14159265 * d * d);
	float k = a * 0.5;
	float vis = 0.25 / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
	float3 highlight = D * vis * NdotL * fresnel * keyLight * ambient;

	// -- Composite --
	float3 colour = behind * (1.0 - fresnel)
		+ env * fresnel * reflectionStrength
		+ highlight
		+ albedo * ambient * albedoStrength;

	// Debug: 1 thickness, 2 roughness, 3 transmission, 4 normal, 5 fresnel (scaled by the local brightness),
	// 6 raw scene at the pixel, 7 blurred scene before tint (6 and 7 should match what is behind)
	if (debugView > 0.5)
	{
		if (debugView < 1.5)		colour = thickness.xxx;
		else if (debugView < 2.5)	colour = roughness.xxx;
		else if (debugView < 3.5)	colour = transmission;
		else if (debugView < 4.5)	colour = N * 0.5 + 0.5;
		else if (debugView < 5.5)	colour = fresnel.xxx;
		if (debugView < 5.5)		colour *= Luminance(ambient) * 4.0;
		else if (debugView < 6.5)	colour = iResolveScene.SampleLevel(sceneSampler, uv, 0).rgb;
		else						colour = BlurScene(sceneUV, blurUV, pixel, rotation, BLUR_TAPS, mipCount);
	}

#ifdef FROST_DEBUG_SOLID
	// hot-reload check: every pixel this material draws turns magenta
	colour = float3(4, 0, 4);
#endif

#if USE_OIT
	// Premultiplied into the fragment list; into the fallback target only when the list is full
	float4 premul = float4(min(max(colour, 0.0), 64512.0) * opacity, opacity);
	if (all(premul == 0.0))
		return 0;
	uint2 pixelPos = (uint2)IN.Position.xy;
	uint slot;
	InterlockedAdd(gOITFragmentCount[pixelPos], 1, slot);
	if (slot < OIT_MAX_FRAGMENTS)
	{
		gOITFragmentData[uint3(pixelPos, slot)] = OIT_PackFragment(premul.rgb, premul.a, IN.Position.z);
		return 0;
	}
	return premul;
#else
	return float4(colour, opacity);
#endif
}
